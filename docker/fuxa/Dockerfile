FROM frangoteam/fuxa:1.3.4

COPY patch-permissions.js /tmp/patch-permissions.js
COPY patch-session-timeout.js /tmp/patch-session-timeout.js

RUN node /tmp/patch-permissions.js \
    && node /tmp/patch-session-timeout.js \
    && rm /tmp/patch-permissions.js \
              /tmp/patch-session-timeout.js
