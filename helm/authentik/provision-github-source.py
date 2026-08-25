from authentik.sources.oauth.models import OAuthSource
from authentik.flows.models import Flow
import os

auth_flow = Flow.objects.get(slug='default-source-authentication')
enroll_flow = Flow.objects.get(slug='default-source-enrollment')

src, created = OAuthSource.objects.get_or_create(
    slug='github',
    defaults=dict(
        name='GitHub',
        provider_type='github',
        consumer_key=os.environ['GITHUB_OAUTH_CLIENT_ID'],
        consumer_secret=os.environ['GITHUB_OAUTH_CLIENT_SECRET'],
        authentication_flow=auth_flow,
        enrollment_flow=enroll_flow,
    ),
)
if not created:
    src.consumer_key = os.environ['GITHUB_OAUTH_CLIENT_ID']
    src.consumer_secret = os.environ['GITHUB_OAUTH_CLIENT_SECRET']
    src.save()

# ponytail: creating the OAuthSource alone doesn't make it show up as a
# login button — it also has to be attached to the login page's
# identification stage. Easy to miss since the stage still loads fine
# without it, just silently renders zero source buttons.
from authentik.stages.identification.models import IdentificationStage
stage = IdentificationStage.objects.get(name='default-authentication-identification')
if src not in stage.sources.all():
    stage.sources.add(src)
    stage.save()

print('github source ready, created=', created, 'sources on login page:', list(stage.sources.values_list('slug', flat=True)))

# Auto-promote admin on enrollment — runs inside Authentik's flow engine
# the moment the admin email logs in for the first time, no manual trigger needed.
from authentik.policies.expression.models import ExpressionPolicy
from authentik.policies.models import PolicyBinding
from authentik.flows.models import FlowStageBinding

admin_email = os.environ['ADMIN_EMAIL']
expr = "from authentik.core.models import Group, UserTypes\nuser = request.context.get('pending_user')\nif user and user.email == '" + admin_email + "':\n    admins = Group.objects.filter(name='authentik Admins').first()\n    if admins:\n        admins.users.add(user)\n    if user.type != UserTypes.INTERNAL:\n        user.type = UserTypes.INTERNAL\n        user.save()\nreturn True\n"
policy, _ = ExpressionPolicy.objects.get_or_create(
    name='auto-promote-admin-on-enrollment',
    defaults=dict(expression=expr),
)
if not _:
    policy.expression = expr
    policy.save()

for binding in FlowStageBinding.objects.filter(target=enroll_flow):
    PolicyBinding.objects.get_or_create(
        target=binding,
        policy=policy,
        defaults=dict(order=0, enabled=True, negate=False, timeout=30),
    )

print('admin auto-promote policy ready for:', admin_email)
