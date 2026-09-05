#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
workflow="$repo_root/.github/workflows/openapi-contract.yml"
documentation="$repo_root/docs/reusable-openapi-ci.md"

test -f "$workflow"
test -f "$documentation"

ruby -ryaml - "$workflow" <<'RUBY'
workflow = YAML.safe_load(File.read(ARGV.fetch(0)), aliases: true)
on = workflow["on"] || workflow[true]
raise "workflow_call trigger is missing" unless on.is_a?(Hash) && on.key?("workflow_call")

inputs = on.fetch("workflow_call").fetch("inputs")
%w[working_directory contract_path generate_command artifact_name].each do |name|
  raise "missing workflow input: #{name}" unless inputs.key?(name)
end

jobs = workflow.fetch("jobs")
raise "validate job is missing" unless jobs.key?("validate")
raise "breaking-change job is missing" unless jobs.key?("breaking-change")
RUBY

required_workflow_fragments=(
  'npx --yes --package "@redocly/cli@2.49.0"'
  'oasdiff_1.29.1_linux_amd64.tar.gz'
  'sha256sum --check --status'
  'github.event.pull_request.base.sha'
  'actions/upload-artifact@'
  'api-breaking-change-approved'
)

for fragment in "${required_workflow_fragments[@]}"; do
  grep -Fq "$fragment" "$workflow"
done

required_documentation_fragments=(
  'openapi-contract.yml'
  'generate_command'
  'api-breaking-change-approved'
  'info.version'
  'Closes'
)

for fragment in "${required_documentation_fragments[@]}"; do
  grep -Fq "$fragment" "$documentation"
done

echo "OpenAPI workflow contract checks passed"
