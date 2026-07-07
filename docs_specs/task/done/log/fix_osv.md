Run google/osv-scanner-action/osv-reporter-action@ffff457756fc02fd3b933aabf3705406f57a2e19
/usr/bin/docker run --name ghcriogoogleosvscanneractionv231_30035d --label 885ddd --workdir /github/workspace --rm -e "INPUT_SCAN-ARGS" -e "HOME" -e "GITHUB_JOB" -e "GITHUB_REF" -e "GITHUB_SHA" -e "GITHUB_REPOSITORY" -e "GITHUB_REPOSITORY_OWNER" -e "GITHUB_REPOSITORY_OWNER_ID" -e "GITHUB_RUN_ID" -e "GITHUB_RUN_NUMBER" -e "GITHUB_RETENTION_DAYS" -e "GITHUB_RUN_ATTEMPT" -e "GITHUB_ACTOR_ID" -e "GITHUB_ACTOR" -e "GITHUB_WORKFLOW" -e "GITHUB_HEAD_REF" -e "GITHUB_BASE_REF" -e "GITHUB_EVENT_NAME" -e "GITHUB_SERVER_URL" -e "GITHUB_API_URL" -e "GITHUB_GRAPHQL_URL" -e "GITHUB_REF_NAME" -e "GITHUB_REF_PROTECTED" -e "GITHUB_REF_TYPE" -e "GITHUB_WORKFLOW_REF" -e "GITHUB_WORKFLOW_SHA" -e "GITHUB_REPOSITORY_ID" -e "GITHUB_TRIGGERING_ACTOR" -e "GITHUB_WORKSPACE" -e "GITHUB_ACTION" -e "GITHUB_EVENT_PATH" -e "GITHUB_ACTION_REPOSITORY" -e "GITHUB_ACTION_REF" -e "GITHUB_PATH" -e "GITHUB_ENV" -e "GITHUB_STEP_SUMMARY" -e "GITHUB_STATE" -e "GITHUB_OUTPUT" -e "RUNNER_OS" -e "RUNNER_ARCH" -e "RUNNER_NAME" -e "RUNNER_ENVIRONMENT" -e "RUNNER_TOOL_CACHE" -e "RUNNER_TEMP" -e "RUNNER_WORKSPACE" -e "ACTIONS_RUNTIME_URL" -e "ACTIONS_RUNTIME_TOKEN" -e "ACTIONS_CACHE_URL" -e "ACTIONS_RESULTS_URL" -e "ACTIONS_ORCHESTRATION_ID" -e GITHUB_ACTIONS=true -e CI=true --entrypoint "/root/osv-reporter" -v "/var/run/docker.sock":"/var/run/docker.sock" -v "/home/runner/work/_temp":"/github/runner_temp" -v "/home/runner/work/_temp/_github_home":"/github/home" -v "/home/runner/work/_temp/_github_workflow":"/github/workflow" -v "/home/runner/work/_temp/_runner_file_commands":"/github/file_commands" -v "/home/runner/work/keikakun_app/keikakun_app":"/github/workspace" ghcr.io/google/osv-scanner-action:v2.3.1  "--output=results.sarif
--new=results.json
--gh-annotations=false
--fail-on-vuln=true"
Total 3 packages affected by 3 known vulnerabilities (0 Critical, 0 High, 2 Medium, 1 Low, 0 Unknown) from 1 ecosystem.
3 vulnerabilities can be fixed.


+-------------------------------------+------+-----------+-------------------+---------+---------------+---------------------------+
| OSV URL                             | CVSS | ECOSYSTEM | PACKAGE           | VERSION | FIXED VERSION | SOURCE                    |
+-------------------------------------+------+-----------+-------------------+---------+---------------+---------------------------+
| https://osv.dev/GHSA-4x5r-pxfx-6jf8 | 3.2  | npm       | @babel/core (dev) | 7.29.0  | 7.29.6        | k_front/package-lock.json |
| https://osv.dev/GHSA-h67p-54hq-rp68 | 5.3  | npm       | js-yaml (dev)     | 4.1.1   | 4.2.0         | k_front/package-lock.json |
| https://osv.dev/GHSA-vmf3-w455-68vh | 6.9  | npm       | tar (dev)         | 7.5.13  | 7.5.16        | k_front/package-lock.json |
+-------------------------------------+------+-----------+-------------------+---------+---------------+---------------------------+
