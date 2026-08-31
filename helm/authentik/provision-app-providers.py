from authentik.providers.oauth2.models import OAuth2Provider, ClientTypes, RedirectURI, RedirectURIMatchingMode, ScopeMapping
from authentik.providers.saml.models import SAMLProvider
from authentik.core.models import Application, PropertyMapping, User, Group, UserTypes
from authentik.flows.models import Flow
from authentik.crypto.models import CertificateKeyPair
import os

admin_email = os.environ['ADMIN_EMAIL']
ts_host = os.environ['TS_HOST']
nx_cloud_app_url = os.environ.get('NX_CLOUD_APP_URL', '')

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
mappings = list(PropertyMapping.objects.filter(name__in=[
    "authentik default OAuth Mapping: OpenID 'openid'",
    "authentik default OAuth Mapping: OpenID 'email'",
    "authentik default OAuth Mapping: OpenID 'profile'",
]))

minio_expr = 'if request.user.email == "' + admin_email + '":\n    return {"policy": "consoleAdmin"}\nreturn {"policy": "readwrite"}'
sm_minio, sm_minio_created = ScopeMapping.objects.get_or_create(name='MinIO policy claim', defaults=dict(scope_name='policy', expression=minio_expr))
if not sm_minio_created:
    sm_minio.expression = minio_expr
    sm_minio.save()

print('minio policy mapping ready, created=', sm_minio_created)

owui_expr = 'if request.user.email == "' + admin_email + '":\n    return {"roles": "admin"}\nreturn {"roles": "user"}'
sm_owui, sm_owui_created = ScopeMapping.objects.get_or_create(name='OpenWebUI roles claim', defaults=dict(scope_name='openwebui_roles', expression=owui_expr))
if not sm_owui_created:
    sm_owui.expression = owui_expr
    sm_owui.save()

print('openwebui roles mapping ready, created=', sm_owui_created)

llm_expr = 'if request.user.email == "' + admin_email + '":\n    return {"litellm_role": "proxy_admin"}\nreturn {"litellm_role": "proxy_viewer"}'
sm_llm, sm_llm_created = ScopeMapping.objects.get_or_create(name='LiteLLM role claim', defaults=dict(scope_name='litellm_role', expression=llm_expr))
if not sm_llm_created:
    sm_llm.expression = llm_expr
    sm_llm.save()

print('litellm role mapping ready, created=', sm_llm_created)

scope_map = {'policy': sm_minio, 'openwebui_roles': sm_owui, 'litellm_role': sm_llm}

apps = [
    dict(name='GitLab', slug='gitlab',
         client_id=os.environ['GITLAB_OIDC_CLIENT_ID'], client_secret=os.environ['GITLAB_OIDC_CLIENT_SECRET'],
         redirect_uris=[f'https://{ts_host}/users/auth/openid_connect/callback']),
    dict(name='MinIO', slug='minio',
         client_id=os.environ['MINIO_OIDC_CLIENT_ID'], client_secret=os.environ['MINIO_OIDC_CLIENT_SECRET'],
         redirect_uris=[f'https://{ts_host}:8445/oauth_callback'], extra_scopes=['policy']),
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
    dict(name='Grafana', slug='grafana',
         client_id=os.environ['GRAFANA_OIDC_CLIENT_ID'], client_secret=os.environ['GRAFANA_OIDC_CLIENT_SECRET'],
         redirect_uris=[f'https://{ts_host}:8451/login/generic_oauth']),
    dict(name='OpenWebUI', slug='openwebui',
         client_id=os.environ['OPENWEBUI_OIDC_CLIENT_ID'], client_secret=os.environ['OPENWEBUI_OIDC_CLIENT_SECRET'],
         redirect_uris=[f'https://{ts_host}:8452/oauth/oidc/callback'], extra_scopes=['openwebui_roles']),
    dict(name='LiteLLM', slug='litellm',
         client_id=os.environ['LITELLM_OIDC_CLIENT_ID'], client_secret=os.environ['LITELLM_OIDC_CLIENT_SECRET'],
         redirect_uris=[f'https://{ts_host}:8453/sso/callback'],
         sub_mode='user_username', extra_scopes=['litellm_role']),
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

# Nx Cloud SAML provider — nx-cloud only supports SAML (no generic OIDC).
# ACS URL = <nx-cloud-url>/auth-callback, SP entity ID = 'nx-private-cloud' (hardcoded by nx-cloud).
if nx_cloud_app_url:
    from authentik.providers.saml.models import SAMLPropertyMapping
    # ponytail: nx-cloud expects attribute name 'email', not the default WS-Federation URI
    nx_cloud_email_map, _ = SAMLPropertyMapping.objects.get_or_create(
        name='Nx Cloud SAML email',
        defaults=dict(saml_name='email', friendly_name='email', expression='return request.user.email'),
    )
    saml_p, saml_created = SAMLProvider.objects.get_or_create(
        name='Nx Cloud',
        defaults=dict(
            authorization_flow=auth_flow,
            acs_url=nx_cloud_app_url + '/auth-callback',
            issuer='https://' + ts_host + ':8443/application/saml/nx-cloud/',
            audience='nx-private-cloud',
            signing_kp=signing_key,
            sign_assertion=True,
            sign_response=True,
            sp_binding='post',
        ),
    )
    if not saml_created:
        saml_p.acs_url = nx_cloud_app_url + '/auth-callback'
        saml_p.issuer = 'https://' + ts_host + ':8443/application/saml/nx-cloud/'
        saml_p.audience = 'nx-private-cloud'
        saml_p.sign_response = True
        saml_p.sp_binding = 'post'
        saml_p.save()
    saml_p.property_mappings.set([nx_cloud_email_map])
    saml_app, saml_app_created = Application.objects.get_or_create(
        slug='nx-cloud',
        defaults=dict(name='Nx Cloud', provider=saml_p),
    )
    if not saml_app_created:
        saml_app.provider = saml_p
        saml_app.save()
    # Print the signing cert so callers can capture it for SAML_CERT env var.
    print('NX_CLOUD_SAML_CERT_START')
    print(signing_key.certificate_data)
    print('NX_CLOUD_SAML_CERT_END')
    print('nx-cloud SAML provider ready, provider_created=', saml_created, 'app_created=', saml_app_created)
else:
    print('nx-cloud SAML provider skipped: NX_CLOUD_APP_URL not set')

