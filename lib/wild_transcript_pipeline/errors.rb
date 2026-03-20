# frozen_string_literal: true

module WildTranscriptPipeline
  class Error < StandardError; end
  class IngestionError < Error; end
  class NormalizationError < Error; end
  class PrivacyError < Error; end
  class ExportError < Error; end
  class ConfigurationError < Error; end
end
