#!/bin/sh

set -e

case "$1" in
    remove|deconfigure|remove-in-favour|deconfigure-in-favour)
        if [ -x "/etc/init.d/nginx" ]; then
            if [ -x "`which invoke-rc.d 2>/dev/null`" ]; then
                invoke-rc.d nginx stop || true
             else
                /etc/init.d/nginx stop || true
             fi
        fi
        ;;
    upgrade|failed-upgrade)
        ;;
    *)
        echo "prerm called with unknown argument \`$1'" >&2
        ;;
esac

exit 0
