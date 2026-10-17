#!/usr/bin/env bash
pgrep -x wlsunset >/dev/null && echo "on" || echo "off"
