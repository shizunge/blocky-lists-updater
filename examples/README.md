# blocky lists updater example

`docker-compose.yml` demonstrates how to configure *lists updater* via environment variables, and to share volumes with a web UI for editing.

`blocky-config.yml` demonstrates how to define groups for blocky to read lists from the *lists updater*.

`post-dl-fix.sh` is used to fix problems in the lists downloaded before the upstream maintainer fixing it. We set environment variable `BLU_POST_DOWNLOAD_CMD=source /scripts/post-dl-fix.sh` to apply it to all lists downloaded.
