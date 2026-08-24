#!/bin/bash
# ponytail: no-op until ADMIN_EMAIL has logged in via SSO once (JIT-creates
# the ccnet emailuser row) — safe to run on every Tilt reload regardless.
# Sets seahub's runtime env directly instead of sourcing seahub.sh's own
# "python-env" case — sourcing breaks seahub.sh's $0-based path detection
# (INSTALLPATH/TOPDIR resolve relative to the CALLER's path, not its own).
set -e
INSTALLPATH=/opt/seafile/seafile-server-13.0.25
export PYTHONPATH="${INSTALLPATH}/seafile/lib/python3/site-packages:${INSTALLPATH}/seafile/lib64/python3/site-packages:${INSTALLPATH}/seahub:${INSTALLPATH}/seahub/thirdpart:${INSTALLPATH}/pro/python"
export SEAFES_DIR="${INSTALLPATH}/pro/python/seafes"
export SEAHUB_DIR="${INSTALLPATH}/seahub"
export SEAHUB_LOG_DIR=/shared/seafile/logs
export SEAFILE_CENTRAL_CONF_DIR=/shared/seafile/conf
export SEAFILE_DATA_DIR=/shared/seafile/seafile-data
export SEAFILE_RPC_PIPE_PATH="${INSTALLPATH}/runtime"
export DJANGO_SETTINGS_MODULE=seahub.settings

cd "${INSTALLPATH}/seahub"
python3 manage.py shell -c "
from seaserv import ccnet_api
u = ccnet_api.get_emailuser('${ADMIN_EMAIL}')
if u:
    ccnet_api.update_emailuser(u.source, u.id, '!', True, u.is_active)
    print('seafile admin ready:', u.email)
else:
    print('seafile admin skipped: no user yet for ${ADMIN_EMAIL} (log in via SSO first)')
"
