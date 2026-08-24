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
