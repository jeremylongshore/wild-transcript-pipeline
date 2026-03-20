# frozen_string_literal: true

require 'time'

require_relative 'wild_transcript_pipeline/version'
require_relative 'wild_transcript_pipeline/errors'
require_relative 'wild_transcript_pipeline/configuration'

require_relative 'wild_transcript_pipeline/models/turn'
require_relative 'wild_transcript_pipeline/models/intent'
require_relative 'wild_transcript_pipeline/models/tool_reference'
require_relative 'wild_transcript_pipeline/models/transcript'
require_relative 'wild_transcript_pipeline/models/transcript_batch'

require_relative 'wild_transcript_pipeline/ingestion/base_adapter'
require_relative 'wild_transcript_pipeline/ingestion/claude_code_adapter'
require_relative 'wild_transcript_pipeline/ingestion/mcp_log_adapter'
require_relative 'wild_transcript_pipeline/ingestion/generic_adapter'

require_relative 'wild_transcript_pipeline/normalization/turn_normalizer'
require_relative 'wild_transcript_pipeline/normalization/intent_detector'
require_relative 'wild_transcript_pipeline/normalization/tool_extractor'

require_relative 'wild_transcript_pipeline/privacy/content_filter'
require_relative 'wild_transcript_pipeline/privacy/redactor'

require_relative 'wild_transcript_pipeline/export/json_exporter'
require_relative 'wild_transcript_pipeline/export/markdown_exporter'

module WildTranscriptPipeline
  class << self
    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield(configuration)
      configuration.freeze!
    end

    def reset_configuration!
      @configuration = Configuration.new
    end

    # Convenience: run the full pipeline on raw input
    # Returns an array of normalized, redacted Transcript objects
    def process(input, adapter:, source_id: nil, config: configuration)
      transcripts = adapter.parse(input, source_id: source_id)
      pipeline = build_pipeline
      transcripts.map { |t| run_pipeline(t, pipeline, config) }
    end

    private

    def build_pipeline
      {
        normalizer: Normalization::TurnNormalizer.new,
        intent_detector: Normalization::IntentDetector.new,
        tool_extractor: Normalization::ToolExtractor.new,
        redactor: Privacy::Redactor.new
      }
    end

    def run_pipeline(transcript, pipeline, config)
      turns = pipeline[:normalizer].normalize(transcript.turns, config: config)
      turns = turns.map { |t| pipeline[:redactor].redact_turn(t, config: config) }
      intents = pipeline[:intent_detector].detect(turns, config: config)
      tool_refs = pipeline[:tool_extractor].extract(turns)
      enriched = build_enriched_transcript(transcript, turns, intents, tool_refs)
      pipeline[:redactor].redact_transcript(enriched, config: config)
    end

    def build_enriched_transcript(transcript, turns, intents, tool_refs)
      Models::Transcript.new(
        source_type: transcript.source_type,
        source_id: transcript.source_id,
        turns: turns,
        intents: intents,
        tool_references: tool_refs,
        metadata: transcript.metadata.merge(processed: true),
        created_at: transcript.created_at
      )
    end
  end
end
