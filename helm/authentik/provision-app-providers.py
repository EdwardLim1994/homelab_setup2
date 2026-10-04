from authentik.providers.oauth2.models import OAuth2Provider, ClientTypes, RedirectURI, RedirectURIMatchingMode, ScopeMapping
from authentik.core.models import Application, PropertyMapping, User, Group, UserTypes
from authentik.flows.models import Flow
from authentik.crypto.models import CertificateKeyPair
import os

admin_email = os.environ['ADMIN_EMAIL']
# Tailnet MagicDNS suffix (e.g. tail1234.ts.net). Each app is reached at
# https://<slug>.<app_domain> via the Tailscale k8s operator.
app_domain = os.environ['APP_DOMAIN']

def app_url(slug):
    return f'https://{slug}.{app_domain}'

admin_user = User.objects.filter(email=admin_email).first()
if admin_user:
    admins_group = Group.objects.get(name='authentik Admins')
    admins_group.users.add(admin_user)
    admins_group.save()
    if admin_user.type != UserTypes.INTERNAL:
        admin_user.type = UserTypes.INTERNAL
        admin_user.save()
    print('authentik admin ready:', admin_user.username)
else:
    print('authentik admin skipped: no user yet for', admin_email)

auth_flow = Flow.objects.get(slug='default-provider-authorization-implicit-consent')
inval_flow = Flow.objects.get(slug='default-provider-invalidation-flow')
signing_key = CertificateKeyPair.objects.filter(name__icontains='authentik Self-signed Certificate').first()
# ponytail: after a fresh Authentik DB, the default OAuth blueprints import
# asynchronously — this null_resource can run before the openid/email/profile
# mappings exist, leaving every provider with no scope mappings and every OIDC
# login failing "Insufficient scope". Wait for them.
import time
_want = [
    "authentik default OAuth Mapping: OpenID 'openid'",
    "authentik default OAuth Mapping: OpenID 'email'",
    "authentik default OAuth Mapping: OpenID 'profile'",
]
for _ in range(60):
    mappings = list(PropertyMapping.objects.filter(name__in=_want))
    if len(mappings) == len(_want):
        break
    print('waiting for default OpenID mappings...', len(mappings), '/', len(_want))
    time.sleep(5)
else:
    raise SystemExit('default OpenID property mappings never appeared')

minio_expr = 'if request.user.email == "' + admin_email + '":\n    return {"policy": "consoleAdmin"}\nreturn {"policy": "readwrite"}'
sm_minio, sm_minio_created = ScopeMapping.objects.get_or_create(name='MinIO policy claim', defaults=dict(scope_name='policy', expression=minio_expr))
if not sm_minio_created:
    sm_minio.expression = minio_expr
    sm_minio.save()

print('minio policy mapping ready, created=', sm_minio_created)

llm_expr = 'if request.user.email == "' + admin_email + '":\n    return {"litellm_role": "proxy_admin"}\nreturn {"litellm_role": "proxy_viewer"}'
sm_llm, sm_llm_created = ScopeMapping.objects.get_or_create(name='LiteLLM role claim', defaults=dict(scope_name='litellm_role', expression=llm_expr))
if not sm_llm_created:
    sm_llm.expression = llm_expr
    sm_llm.save()

print('litellm role mapping ready, created=', sm_llm_created)

owui_expr = 'if request.user.email == "' + admin_email + '":\n    return {"roles": "admin"}\nreturn {"roles": "user"}'
sm_owui, sm_owui_created = ScopeMapping.objects.get_or_create(name='OpenWebUI roles claim', defaults=dict(scope_name='openwebui_roles', expression=owui_expr))
if not sm_owui_created:
    sm_owui.expression = owui_expr
    sm_owui.save()

print('openwebui roles mapping ready, created=', sm_owui_created)

sonar_expr = 'if request.user.email == "' + admin_email + '":\n    return {"groups": ["sonar-administrators"]}\nreturn {"groups": ["sonar-users"]}'
sm_sonar, sm_sonar_created = ScopeMapping.objects.get_or_create(name='SonarQube groups claim', defaults=dict(scope_name='groups', expression=sonar_expr))
if not sm_sonar_created:
    sm_sonar.expression = sonar_expr
    sm_sonar.save()

print('sonarqube groups mapping ready, created=', sm_sonar_created)

scope_map = {'policy': sm_minio, 'litellm_role': sm_llm, 'openwebui_roles': sm_owui, 'groups': sm_sonar}

apps = [
    dict(name='GitLab', slug='gitlab',
         client_id=os.environ['GITLAB_OIDC_CLIENT_ID'], client_secret=os.environ['GITLAB_OIDC_CLIENT_SECRET'],
         redirect_uris=[app_url('gitlab') + '/users/auth/openid_connect/callback']),
    dict(name='MinIO', slug='minio',
         client_id=os.environ['MINIO_OIDC_CLIENT_ID'], client_secret=os.environ['MINIO_OIDC_CLIENT_SECRET'],
         redirect_uris=[app_url('minio-console') + '/oauth_callback'], extra_scopes=['policy']),
    dict(name='n8n', slug='n8n',
         client_id=os.environ['N8N_OIDC_CLIENT_ID'], client_secret=os.environ['N8N_OIDC_CLIENT_SECRET'],
         redirect_uris=[app_url('n8n') + '/auth/oidc/callback']),
    dict(name='SonarQube', slug='sonarqube',
         client_id=os.environ['SONARQUBE_OIDC_CLIENT_ID'], client_secret=os.environ['SONARQUBE_OIDC_CLIENT_SECRET'],
         redirect_uris=[app_url('sonarqube') + '/oauth2/callback/oidc'], extra_scopes=['groups']),
    dict(name='Nextcloud', slug='nextcloud',
         client_id=os.environ['NEXTCLOUD_OIDC_CLIENT_ID'], client_secret=os.environ['NEXTCLOUD_OIDC_CLIENT_SECRET'],
         redirect_uris=[app_url('nextcloud') + '/apps/sociallogin/custom_oidc/authentik']),
    dict(name='ArgoCD', slug='argocd',
         client_id=os.environ['ARGOCD_OIDC_CLIENT_ID'], client_secret=os.environ['ARGOCD_OIDC_CLIENT_SECRET'],
         redirect_uris=[app_url('argocd') + '/auth/callback']),
    dict(name='Grafana', slug='grafana',
         client_id=os.environ['GRAFANA_OIDC_CLIENT_ID'], client_secret=os.environ['GRAFANA_OIDC_CLIENT_SECRET'],
         redirect_uris=[app_url('grafana') + '/login/generic_oauth']),
    dict(name='LiteLLM', slug='litellm',
         client_id=os.environ['LITELLM_OIDC_CLIENT_ID'], client_secret=os.environ['LITELLM_OIDC_CLIENT_SECRET'],
         redirect_uris=[app_url('litellm') + '/sso/callback'],
         sub_mode='user_username', extra_scopes=['litellm_role']),
    dict(name='OpenWebUI', slug='openwebui',
         client_id=os.environ['OPENWEBUI_OIDC_CLIENT_ID'], client_secret=os.environ['OPENWEBUI_OIDC_CLIENT_SECRET'],
         redirect_uris=[app_url('openwebui') + '/oauth/oidc/callback'], extra_scopes=['openwebui_roles']),
    dict(name='Kafbat Kafka UI', slug='kafka-ui',
         client_id=os.environ['KAFKA_UI_OIDC_CLIENT_ID'], client_secret=os.environ['KAFKA_UI_OIDC_CLIENT_SECRET'],
         redirect_uris=[app_url('kafka-ui') + '/login/oauth2/code/authentik']),
    dict(name='Harbor', slug='harbor',
         client_id=os.environ['HARBOR_OIDC_CLIENT_ID'], client_secret=os.environ['HARBOR_OIDC_CLIENT_SECRET'],
         redirect_uris=[app_url('harbor') + '/c/oidc/callback']),
    dict(name='Taiga', slug='taiga',
         client_id=os.environ['TAIGA_OIDC_CLIENT_ID'], client_secret=os.environ['TAIGA_OIDC_CLIENT_SECRET'],
         # mozilla_django_oidc's standard callback path, mounted at /oidc/ by
         # taiga-contrib-oidc-auth's urls.py (see helm/taiga/README notes).
         redirect_uris=[app_url('taiga') + '/oidc/callback/']),
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
            sub_mode=a.get('sub_mode', 'hashed_user_id'),
            include_claims_in_id_token=True,
            redirect_uris=[RedirectURI(matching_mode=RedirectURIMatchingMode.STRICT, url=u) for u in a['redirect_uris']],
        ),
    )
    if not created:
        p.client_id = a['client_id']
        p.client_secret = a['client_secret']
        p.sub_mode = a.get('sub_mode', 'hashed_user_id')
        p.redirect_uris = [RedirectURI(matching_mode=RedirectURIMatchingMode.STRICT, url=u) for u in a['redirect_uris']]
    p.property_mappings.set(mappings + [scope_map[s] for s in a.get('extra_scopes', [])])
    p.save()
    app, created2 = Application.objects.get_or_create(slug=a['slug'], defaults=dict(name=a['name'], provider=p))
    if not created2:
        app.provider = p
        app.save()
    print('provider ready:', a['slug'], 'provider_created=', created, 'app_created=', created2)

print('all providers done')

