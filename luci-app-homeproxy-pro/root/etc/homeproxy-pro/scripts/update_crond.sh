#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
#
# Subscription auto-update, run from the crontab entry that
# runtime/service.sh installs when subscription.auto_update is on.
#
# The resource lists used to be refreshed from this same script. They are not
# any more: they have their own entry (update_resources_cron.sh), because a
# subscription switch had been deciding whether the firewall's mainland address
# set was still current. See hp_sync_resource_cron() in runtime/service.sh.

SCRIPTS_DIR="/etc/homeproxy-pro/scripts"

"$SCRIPTS_DIR"/update_subscriptions.uc
