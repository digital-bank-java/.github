#!/usr/bin/env ruby

# Lightweight contract guard for the repository-owned AsyncAPI documents.
# Runtime Schema Registry validation remains a platform responsibility.

require "yaml"

CONTRACT_GLOB = File.expand_path("../docs/contracts/*-asyncapi.yml", __dir__)
REQUIRED_EVENT_FIELDS = %w[
  eventId eventType schemaVersion producer occurredAt aggregateId
  correlationId causationId
].freeze
REQUIRED_HEADER_FIELDS = %w[
  event-id correlation-id causation-id producer schema-version occurred-at
].freeze
REQUIRED_CHANNEL_FIELDS = %w[
  address messages bindings x-producer x-consumers x-partition-key
  x-delivery-semantics x-dead-letter-topic x-dead-letter-policy
].freeze

def fail_with(path, message)
  warn "#{path}: #{message}"
  exit 1
end

def lookup(document, reference, path)
  unless reference.is_a?(String) && reference.start_with?("#/")
    fail_with(path, "reference must be a local JSON pointer: #{reference.inspect}")
  end

  reference[2..].split("/").reduce(document) do |value, token|
    key = token.gsub("~1", "/").gsub("~0", "~")
    unless value.is_a?(Hash) && value.key?(key)
      fail_with(path, "reference target does not exist: #{reference}")
    end
    value[key]
  end
end

def expect(condition, path, message)
  fail_with(path, message) unless condition
end

files = Dir[CONTRACT_GLOB].sort
expect(!files.empty?, "docs/contracts", "no AsyncAPI contracts found")

files.each do |file|
  document = YAML.safe_load_file(file, aliases: true)
  relative = file.delete_prefix("#{Dir.pwd}/")
  expect(document.is_a?(Hash), relative, "document must be a YAML mapping")
  expect(document["asyncapi"].to_s.start_with?("3."), relative, "AsyncAPI 3.x metadata is required")
  expect(document.dig("info", "title"), relative, "info.title is required")
  expect(document.dig("info", "version"), relative, "info.version is required")
  expect(document.dig("info", "description"), relative, "info.description is required")
  expect(document["defaultContentType"] == "application/json", relative,
         "defaultContentType must be application/json")

  registry = document["x-schema-registry"]
  expect(registry.is_a?(Hash), relative, "x-schema-registry metadata is required")
  expect(registry["compatibility"] == "BACKWARD_TRANSITIVE", relative,
         "Schema Registry compatibility must be BACKWARD_TRANSITIVE")
  expect(registry["subjects"].is_a?(Hash), relative, "Schema Registry subjects are required")

  channels = document["channels"]
  operations = document["operations"]
  components = document["components"]
  expect(channels.is_a?(Hash) && !channels.empty?, relative, "channels are required")
  expect(operations.is_a?(Hash) && !operations.empty?, relative, "operations are required")
  expect(components.is_a?(Hash), relative, "components are required")
  expect(components["messages"].is_a?(Hash), relative, "components.messages are required")
  expect(components["schemas"].is_a?(Hash), relative, "components.schemas are required")
  expect(registry["subjects"].keys.sort == channels.keys.sort, relative,
         "Schema Registry subjects must match channel addresses")

  channels.each do |channel_name, channel|
    path = "#{relative} channels.#{channel_name}"
    expect(channel.is_a?(Hash), path, "channel must be a mapping")
    REQUIRED_CHANNEL_FIELDS.each { |field| expect(channel.key?(field), path, "#{field} is required") }
    expect(channel.dig("bindings", "kafka").is_a?(Hash), path, "Kafka binding is required")
    expect(channel["messages"].is_a?(Hash) && !channel["messages"].empty?, path,
           "at least one channel message is required")
    channel["messages"].each do |message_name, message_reference|
      message = message_reference["$ref"] ? lookup(document, message_reference["$ref"], "#{path}.messages.#{message_name}") : message_reference
      expect(message.is_a?(Hash), path, "channel message must resolve to a mapping")
      payload = message["payload"]
      headers = message["headers"]
      expect(payload.is_a?(Hash) && payload["$ref"], path, "message payload reference is required")
      expect(headers.is_a?(Hash) && headers["$ref"], path, "message headers reference is required")
      payload_schema = lookup(document, payload["$ref"], "#{path}.messages.#{message_name}.payload")
      header_schema = lookup(document, headers["$ref"], "#{path}.messages.#{message_name}.headers")
      expect(payload_schema.is_a?(Hash), path, "payload schema must resolve to a mapping")
      expect(header_schema.is_a?(Hash), path, "header schema must resolve to a mapping")
      required = payload_schema.fetch("required", []) + payload_schema.fetch("allOf", []).filter_map do |part|
        part["$ref"] ? lookup(document, part["$ref"], path).fetch("required", []) : []
      end.flatten
      expect(REQUIRED_EVENT_FIELDS.all? { |field| required.include?(field) }, path,
             "payload must require all common event metadata fields")
      expect(REQUIRED_HEADER_FIELDS.all? { |field| header_schema.fetch("required", []).include?(field) },
             path, "headers must require all common event metadata fields")
    end
  end

  operations.each do |operation_name, operation|
    path = "#{relative} operations.#{operation_name}"
    expect(operation["action"] == "send", path, "operation action must be send")
    channel_reference = operation.dig("channel", "$ref")
    expect(channel_reference, path, "operation channel reference is required")
    channel = lookup(document, channel_reference, path)
    message_references = operation["messages"]
    expect(message_references.is_a?(Array) && !message_references.empty?, path,
           "operation message references are required")
    message_references.each { |message_reference| lookup(document, message_reference["$ref"], path) }
    expect(channel["messages"].keys.any? do |name|
      message_references.any? { |reference| reference["$ref"].end_with?("/messages/#{name}") }
    end, path, "operation must reference a message from its channel")
  end
end

puts "Validated #{files.length} AsyncAPI contract documents"
