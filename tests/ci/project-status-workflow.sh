#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
workflow="$repo_root/.github/workflows/project-status.yml"
caller="$repo_root/.github/workflow-templates/project-status.yml"
caller_metadata="$repo_root/.github/workflow-templates/project-status.properties.json"
documentation="$repo_root/docs/reusable-project-status.md"
caller_documentation="$repo_root/docs/project-status-caller-template.md"

test -f "$workflow"
test -f "$caller"
test -f "$caller_metadata"
test -f "$documentation"
test -f "$caller_documentation"

ruby -rjson -ryaml - "$workflow" "$caller" "$caller_metadata" <<'RUBY'
workflow_path, caller_path, metadata_path = ARGV

def load_yaml(path)
  YAML.safe_load(File.read(path), aliases: true)
end

workflow = load_yaml(workflow_path)
workflow_on = workflow["on"] || workflow[true]
raise "workflow_call trigger is missing" unless workflow_on.is_a?(Hash) && workflow_on.key?("workflow_call")

inputs = workflow_on.fetch("workflow_call").fetch("inputs")
%w[project_owner project_number status_field_name].each do |name|
  raise "missing workflow input: #{name}" unless inputs.key?(name)
end

secrets = workflow_on.fetch("workflow_call").fetch("secrets")
raise "project_token secret must be optional" unless secrets.dig("project_token", "required") == false
raise "workflow permissions must be empty" unless workflow.fetch("permissions") == {}
raise "update-status job is missing" unless workflow.fetch("jobs").key?("update-status")

caller = load_yaml(caller_path)
caller_on = caller["on"] || caller[true]
raise "caller must use pull_request_target" unless caller_on.key?("pull_request_target")
types = caller_on.fetch("pull_request_target").fetch("types")
%w[opened reopened ready_for_review closed].each do |type|
  raise "caller is missing pull request type: #{type}" unless types.include?(type)
end

caller_ref = caller.fetch("jobs").fetch("project-status").fetch("uses")
raise "caller workflow reference must use a full commit SHA" unless caller_ref.match?(/@[0-9a-f]{40}\z/)
raise "caller workflow reference must not use a placeholder SHA" if caller_ref.end_with?("@#{'0' * 40}")
caller_job = caller.fetch("jobs").fetch("project-status")
raise "caller permissions must be empty" unless caller.fetch("permissions") == {}
raise "caller job permissions must be empty" unless caller_job.fetch("permissions") == {}
raise "caller must pass project_token" unless caller_job.dig("secrets", "project_token")
raise "caller must not inherit unrelated secrets" if caller_job.fetch("secrets").values.any? { |value| value == "inherit" }

metadata = JSON.parse(File.read(metadata_path))
raise "workflow template name is missing" unless metadata.fetch("name") == "GitHub Project status"
RUBY

required_workflow_fragments=(
  'pull_request_target'
  'opened|reopened'
  'ready_for_review'
  'PR_MERGED'
  'target_status="Done"'
  'updateProjectV2ItemFieldValue'
  'singleSelectOptionId'
  'projectV2'
  '::warning::'
  'leave the current Project status unchanged'
)

for fragment in "${required_workflow_fragments[@]}"; do
  grep -Fq "$fragment" "$workflow"
done

required_documentation_fragments=(
  'project-status.yml'
  'PROJECT_STATUS_TOKEN'
  'Projects: read/write'
  'pull_request_target'
  'without a merge'
  'In progress'
  'In review'
  'Done'
)

for fragment in "${required_documentation_fragments[@]}"; do
  grep -Fq "$fragment" "$documentation"
done

required_caller_documentation_fragments=(
  'project-status.yml'
  'PROJECT_STATUS_TOKEN'
  'permissions: {}'
  'pull_request_target'
  'never merges pull requests'
  'secrets: inherit'
  'Failure Handling'
  'Adoption Steps'
)

for fragment in "${required_caller_documentation_fragments[@]}"; do
  grep -Fq "$fragment" "$caller_documentation"
done

if grep -Eq 'gh[[:space:]]+pr[[:space:]]+merge|pull_request[[:space:]]*:[[:space:]]*write' "$workflow" "$caller"; then
  echo "project status workflows must not merge pull requests or request pull request write access" >&2
  exit 1
fi

echo "Project status workflow contract checks passed"
