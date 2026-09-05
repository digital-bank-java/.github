#!/usr/bin/env bash
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
contract="${1:-${repository_root}/docs/contracts/account-reservation-transfer-workflow-asyncapi.yml}"

CONTRACT_PATH="${contract}" ruby <<'RUBY'
require "yaml"

contract_path = ENV.fetch("CONTRACT_PATH")
abort "contract does not exist: #{contract_path}" unless File.file?(contract_path)

document = YAML.load_file(contract_path, aliases: true)

def assert(condition, message)
  raise message unless condition
end

expected_channels = {
  "account.reservation.requested.v1" => {
    "message" => "AccountReservationRequestedV1",
    "producer" => "transaction-service",
    "consumers" => ["account-service"],
    "partition_key" => "sourceAccountId",
    "kind" => "command"
  },
  "account.reservation.release-requested.v1" => {
    "message" => "AccountReservationReleaseRequestedV1",
    "producer" => "transaction-service",
    "consumers" => ["account-service"],
    "partition_key" => "sourceAccountId",
    "kind" => "command"
  },
  "account.reservation.accepted.v1" => {
    "message" => "AccountReservationAcceptedV1",
    "producer" => "account-service",
    "consumers" => ["transaction-service"],
    "partition_key" => "sourceAccountId",
    "kind" => "event"
  },
  "account.reservation.rejected.v1" => {
    "message" => "AccountReservationRejectedV1",
    "producer" => "account-service",
    "consumers" => ["transaction-service"],
    "partition_key" => "sourceAccountId",
    "kind" => "event"
  },
  "account.reservation.released.v1" => {
    "message" => "AccountReservationReleasedV1",
    "producer" => "account-service",
    "consumers" => ["transaction-service"],
    "partition_key" => "sourceAccountId",
    "kind" => "event"
  },
  "account.reservation.expired.v1" => {
    "message" => "AccountReservationExpiredV1",
    "producer" => "account-service",
    "consumers" => ["transaction-service"],
    "partition_key" => "sourceAccountId",
    "kind" => "event"
  },
  "events.transfer.created.v1" => {
    "message" => "TransferCreatedV1",
    "producer" => "transaction-service",
    "consumers" => ["notification-service"],
    "partition_key" => "transactionId",
    "kind" => "event"
  },
  "events.transfer.completed.v1" => {
    "message" => "TransferCompletedV1",
    "producer" => "transaction-service",
    "consumers" => ["notification-service"],
    "partition_key" => "transactionId",
    "kind" => "event"
  },
  "events.transfer.failed.v1" => {
    "message" => "TransferFailedV1",
    "producer" => "transaction-service",
    "consumers" => ["notification-service"],
    "partition_key" => "transactionId",
    "kind" => "event"
  }
}.freeze

required_headers = %w[
  event-id
  correlation-id
  causation-id
  producer
  schema-version
  occurred-at
].freeze

required_envelope_fields = %w[
  eventId
  eventType
  schemaVersion
  producer
  occurredAt
  aggregateId
  correlationId
  causationId
  transactionId
  reservationRequestId
].freeze

assert(document.fetch("asyncapi") == "3.0.0", "contract must use AsyncAPI 3.0.0")
assert(document.dig("info", "version") == "1.0.0", "contract version must be 1.0.0")
assert(document.fetch("defaultContentType") == "application/json", "default content type must be JSON")

registry = document.fetch("x-schema-registry")
assert(registry.fetch("compatibility") == "BACKWARD_TRANSITIVE", "Schema Registry compatibility must be BACKWARD_TRANSITIVE")
assert(registry.fetch("subjectStrategy") == "TopicNameStrategy", "Schema Registry must use TopicNameStrategy")
assert(registry.fetch("subjects").keys.sort == expected_channels.keys.sort, "every channel must have one registry subject")
expected_channels.each_key do |topic|
  assert(registry.dig("subjects", topic) == "#{topic}-value", "#{topic} must use its TopicNameStrategy value subject")
end

delivery = document.fetch("x-delivery-and-processing")
assert(delivery.fetch("semantics") == "at-least-once", "delivery must be at-least-once")
%w[producerRetries consumerRetries deadLetter duplicateHandling outOfOrderHandling ordering].each do |rule|
  assert(delivery.fetch(rule).is_a?(String) && !delivery.fetch(rule).empty?, "delivery rule #{rule} must be documented")
end

headers = document.dig("components", "schemas", "WorkflowMessageHeaders")
assert(headers.fetch("additionalProperties") == false, "headers must reject undeclared properties")
assert(headers.fetch("required").sort == required_headers.sort, "required Kafka headers do not match the governed envelope")
required_headers.each do |header|
  assert(headers.dig("properties", header), "missing Kafka header #{header}")
end

envelope = document.dig("components", "schemas", "WorkflowMessageEnvelope")
assert(envelope.fetch("additionalProperties") == true, "payload envelope must permit additive fields")
required_envelope_fields.each do |field|
  assert(envelope.fetch("required").include?(field), "envelope must require #{field}")
  assert(envelope.dig("properties", field), "envelope must define #{field}")
end

channels = document.fetch("channels")
messages = document.dig("components", "messages")
schemas = document.dig("components", "schemas")

assert(channels.keys.sort == expected_channels.keys.sort, "contract channels differ from the governed workflow surface")

expected_channels.each do |topic, expectation|
  channel = channels.fetch(topic)
  message_key = channel.fetch("messages").keys.fetch(0)
  message_ref = channel.dig("messages", message_key, "$ref")

  assert(channel.fetch("address") == topic, "#{topic} address must match the channel key")
  assert(channel.fetch("x-producer") == expectation.fetch("producer"), "#{topic} producer ownership is incorrect")
  assert(channel.fetch("x-consumers") == expectation.fetch("consumers"), "#{topic} consumer ownership is incorrect")
  assert(channel.fetch("x-partition-key") == expectation.fetch("partition_key"), "#{topic} partition key is incorrect")
  assert(channel.fetch("x-message-kind") == expectation.fetch("kind"), "#{topic} command/event classification is incorrect")
  assert(channel.fetch("x-delivery-semantics").start_with?("at-least-once"), "#{topic} must declare at-least-once delivery")
  assert(channel.fetch("x-dead-letter-topic") == "#{topic}.dlq", "#{topic} must use a topic-specific DLQ")
  assert(channel.fetch("x-ordering").include?(expectation.fetch("partition_key")), "#{topic} ordering must name its partition key")
  assert(message_ref == "#/components/messages/#{expectation.fetch("message")}", "#{topic} message reference is incorrect")
  assert(channel.dig("bindings", "kafka", "topic") == topic, "#{topic} Kafka binding must match its address")

  message = messages.fetch(expectation.fetch("message"))
  payload_ref = message.dig("payload", "$ref")
  assert(message.dig("headers", "$ref") == "#/components/schemas/WorkflowMessageHeaders", "#{topic} must use the governed headers")
  assert(payload_ref == "#/components/schemas/#{expectation.fetch("message")}", "#{topic} payload schema reference is incorrect")

  schema = schemas.fetch(expectation.fetch("message"))
  assert(schema.fetch("allOf").any? { |item| item["$ref"] == "#/components/schemas/WorkflowMessageEnvelope" }, "#{topic} must use the governed envelope")

  specialization = schema.fetch("allOf").find { |item| item.key?("properties") }
  assert(specialization.fetch("additionalProperties") == true, "#{topic} payload specialization must permit additive fields")
  assert(specialization.dig("properties", "eventType", "const") == message.fetch("name"), "#{topic} eventType must match the message name")
  assert(specialization.dig("properties", "producer", "const") == expectation.fetch("producer"), "#{topic} payload producer must match channel ownership")
  assert(specialization.dig("properties", "schemaVersion", "const") == "1.0.0", "#{topic} schema version must be 1.0.0")
end

workflow = document.fetch("x-workflow-rules")
%w[reservationAccepted reservationRejected reservationReleased reservationExpired transferCompleted transferFailed].each do |outcome|
  assert(workflow.fetch(outcome).is_a?(String) && !workflow.fetch(outcome).empty?, "workflow outcome #{outcome} must be unambiguous")
end

compatibility = document.fetch("x-compatibility-rules")
%w[withinMajorVersion breakingChanges parallelMigration consumerBehavior].each do |rule|
  assert(compatibility.fetch(rule).is_a?(String) && !compatibility.fetch(rule).empty?, "compatibility rule #{rule} must be documented")
end

amount = schemas.fetch("PositiveDecimalAmount")
assert(amount.fetch("type") == "string", "amounts must be decimal strings")
assert(amount.fetch("pattern").include?("{1,4}"), "amounts must allow at most four fractional digits")

release_request = schemas.fetch("AccountReservationReleaseRequestedV1").fetch("allOf").find { |item| item.key?("properties") }
release_command_reasons = release_request.dig("properties", "reason", "enum")
assert(!release_command_reasons.include?("LEDGER_POSTING_FAILED"), "ledger failure must release through the #137 ledger event, not a duplicate Transaction Service command")

released_event = schemas.fetch("AccountReservationReleasedV1").fetch("allOf").find { |item| item.key?("properties") }
release_outcome_reasons = released_event.dig("properties", "releaseReason", "enum")
assert(release_outcome_reasons.include?("LEDGER_POSTING_FAILED"), "released events must classify releases caused by the #137 ledger failure event")

failed_transfer = schemas.fetch("TransferFailedV1")
failed_compensation_rule = failed_transfer.fetch("allOf").find do |rule|
  rule.dig("if", "properties", "compensationStatus", "const") == "FAILED"
end
assert(failed_compensation_rule, "failed transfer schema must define the failed-compensation rule")
assert(failed_compensation_rule.dig("then", "properties", "manualReviewRequired", "const") == true, "failed compensation must require manual review")

puts "validated #{expected_channels.length} workflow channels in #{contract_path}"
RUBY
