# frozen_string_literal: true

module WildTranscriptPipeline
  class Configuration
    attr_reader :redaction_marker,
                :max_turn_content_length,
                :max_turns_per_transcript,
                :strip_file_contents,
                :strip_absolute_paths,
                :custom_patterns,
                :intent_confidence_threshold

    def initialize
      @redaction_marker = '[REDACTED]'
      @max_turn_content_length = 10_000
      @max_turns_per_transcript = 1_000
      @strip_file_contents = true
      @strip_absolute_paths = true
      @custom_patterns = []
      @intent_confidence_threshold = 0.5
    end

    def redaction_marker=(value)
      check_frozen!
      raise ConfigurationError, 'redaction_marker must be a non-empty String' unless valid_string?(value)

      @redaction_marker = value.freeze
    end

    def max_turn_content_length=(value)
      check_frozen!
      unless value.is_a?(Integer) && value >= 1
        raise ConfigurationError, "max_turn_content_length must be a positive Integer, got: #{value.inspect}"
      end

      @max_turn_content_length = value
    end

    def max_turns_per_transcript=(value)
      check_frozen!
      unless value.is_a?(Integer) && value >= 1
        raise ConfigurationError, "max_turns_per_transcript must be a positive Integer, got: #{value.inspect}"
      end

      @max_turns_per_transcript = value
    end

    def strip_file_contents=(value)
      check_frozen!
      unless [true, false].include?(value)
        raise ConfigurationError, "strip_file_contents must be true or false, got: #{value.inspect}"
      end

      @strip_file_contents = value
    end

    def strip_absolute_paths=(value)
      check_frozen!
      unless [true, false].include?(value)
        raise ConfigurationError, "strip_absolute_paths must be true or false, got: #{value.inspect}"
      end

      @strip_absolute_paths = value
    end

    def custom_patterns=(value)
      check_frozen!
      raise ConfigurationError, 'custom_patterns must be an Array' unless value.is_a?(Array)

      invalid = value.grep_v(Regexp)
      unless invalid.empty?
        raise ConfigurationError, "custom_patterns entries must all be Regexp, got: #{invalid.map(&:class).uniq}"
      end

      @custom_patterns = value.freeze
    end

    def intent_confidence_threshold=(value)
      check_frozen!
      unless value.is_a?(Numeric) && value >= 0.0 && value <= 1.0
        raise ConfigurationError,
              "intent_confidence_threshold must be between 0.0 and 1.0, got: #{value.inspect}"
      end

      @intent_confidence_threshold = value.to_f
    end

    def freeze!
      @custom_patterns = @custom_patterns.freeze
      freeze
    end

    private

    def check_frozen!
      raise FrozenError, "can't modify frozen #{self.class}" if frozen?
    end

    def valid_string?(value)
      value.is_a?(String) && !value.strip.empty?
    end
  end
end
