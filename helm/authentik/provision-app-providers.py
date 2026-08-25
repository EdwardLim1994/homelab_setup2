from authentik.providers.oauth2.models import OAuth2Provider, ClientTypes, RedirectURI, RedirectURIMatchingMode, ScopeMapping
from authentik.core.models import Application, PropertyMapping, User, Group, UserTypes
from authentik.flows.models import Flow
from authentik.crypto.models import CertificateKeyPair
import os

# ponytail: full Authentik admin (superuser-equivalent) for the designated
# admin — a no-op until they've logged in at least once via GitHub SSO
# (JIT-provisions the User row), since there's nothing to add to the group
# before that. Two things are required, not just one: (1) group membership
# grants superuser permissions but (2) the admin *interface* additionally
# requires user.type == "internal" — GitHub-SSO-provisioned users default
# to "external", which renders "Interface can only be accessed by internal
# users" even for a superuser. Both get set every run, idempotently.
admin_user = User.objects.filter(email=os.environ['ADMIN_EMAIL']).first()
if admin_user:
    admins_group = Group.objects.get(name='authentik Admins')
    admins_group.users.add(admin_user)
    admins_group.save()
    if admin_user.type != UserTypes.INTERNAL:
        admin_user.type = UserTypes.INTERNAL
        admin_user.save()
    print('authentik admin ready:', admin_user.username, 'type:', admin_user.type)
else:
    print('authentik admin skipped: no user yet for', os.environ['ADMIN_EMAIL'], '(log in via GitHub SSO first)')

auth_flow = Flow.objects.get(slug='default-provider-authorization-implicit-consent')
inval_flow = Flow.objects.get(slug='default-provider-invalidation-flow')
signing_key = CertificateKeyPair.objects.filter(name__icontains='authentik Self-signed Certificate').first()
mappings = PropertyMapping.objects.filter(name__in=[
    "authentik default OAuth Mapping: OpenID 'openid'",
    "authentik default OAuth Mapping: OpenID 'email'",
    "authentik default OAuth Mapping: OpenID 'profile'",
])

ts_host = os.environ["TS_HOST"]
apps = [
    dict(name='GitLab', slug='gitlab',
         client_id=os.environ['GITLAB_OIDC_CLIENT_ID'], client_secret=os.environ['GITLAB_OIDC_CLIENT_SECRET'],
         redirect_uris=[f'https://{ts_host}:8444/users/auth/openid_connect/callback']),
    dict(name='MinIO', slug='minio',
         client_id=os.environ['MINIO_OIDC_CLIENT_ID'], client_secret=os.environ['MINIO_OIDC_CLIENT_SECRET'],
         redirect_uris=[f'https://{ts_host}:8445/oauth_callback']),
    dict(name='n8n', slug='n8n',
         client_id=os.environ['N8N_OIDC_CLIENT_ID'], client_secret=os.environ['N8N_OIDC_CLIENT_SECRET'],
         redirect_uris=[f'https://{ts_host}:8447/auth/oidc/callback']),
    dict(name='SonarQube', slug='sonarqube',
         client_id=os.environ['SONARQUBE_OIDC_CLIENT_ID'], client_secret=os.environ['SONARQUBE_OIDC_CLIENT_SECRET'],
         redirect_uris=[f'https://{ts_host}:8448/oauth2/callback/oidc']),
    dict(name='Seafile', slug='seafile',
         client_id=os.environ['SEAFILE_OIDC_CLIENT_ID'], client_secret=os.environ['SEAFILE_OIDC_CLIENT_SECRET'],
         redirect_uris=[f'https://{ts_host}:8449/oauth/callback/']),
    dict(name='ArgoCD', slug='argocd',
         client_id=os.environ['ARGOCD_OIDC_CLIENT_ID'], client_secret=os.environ['ARGOCD_OIDC_CLIENT_SECRET'],
         redirect_uris=[f'https://{ts_host}:8450/auth/callback']),
]

for a in apps:
    p, created = OAuth2Provider.objects.get_or_create(
        name=a['name'],
        defaults=dict(
            client_id=a['client_id'],
            client_secret=a['client_secret'],
            client_type=ClientTypes.CONFIDENTIAL,
            authorization_flow=auth_flow,
            invalidation_flow=inval_flow,
            signing_key=signing_key,
            sub_mode='hashed_user_id',
            include_claims_in_id_token=True,
            redirect_uris=[RedirectURI(matching_mode=RedirectURIMatchingMode.STRICT, url=u) for u in a['redirect_uris']],
        ),
    )
    if not created:
        p.client_id = a['client_id']
        p.client_secret = a['client_secret']
        p.redirect_uris = [RedirectURI(matching_mode=RedirectURIMatchingMode.STRICT, url=u) for u in a['redirect_uris']]
    p.property_mappings.set(mappings)
    p.save()
    app, created2 = Application.objects.get_or_create(slug=a['slug'], defaults=dict(name=a['name'], provider=p))
    if not created2:
        app.provider = p
        app.save()
    print('provider ready:', a['slug'], 'provider_created=', created, 'app_created=', created2)

# ponytail: MinIO's policy claim scope mapping — MinIO's own policy engine
# reads this custom "policy" claim from the ID token. consoleAdmin (MinIO's
# built-in full-admin canned policy) for the designated admin, readwrite
# for everyone else.
admin_email = os.environ['ADMIN_EMAIL']
minio_policy_expression = (
    'if request.user.email == "' + admin_email + '":\n'
    '    return {"policy": "consoleAdmin"}\n'
    'return {"policy": "readwrite"}'
)
sm, created = ScopeMapping.objects.get_or_create(
    name='MinIO policy claim',
    defaults=dict(scope_name='policy', expression=minio_policy_expression),
)
if not created:
    sm.expression = minio_policy_expression
    sm.save()

minio_provider = OAuth2Provider.objects.get(name='MinIO')
current = list(minio_provider.property_mappings.all())
if sm not in current:
    minio_provider.property_mappings.set(current + [sm])
    minio_provider.save()

print('minio policy mapping ready, created=', created)
