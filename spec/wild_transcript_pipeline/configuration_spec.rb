# frozen_string_literal: true

RSpec.describe WildTranscriptPipeline::Configuration do
  subject(:config) { described_class.new }

  describe '#initialize' do
    it 'sets redaction_marker to [REDACTED]' do
      expect(config.redaction_marker).to eq('[REDACTED]')
    end

    it 'sets max_turn_content_length to 10_000' do
      expect(config.max_turn_content_length).to eq(10_000)
    end

    it 'sets max_turns_per_transcript to 1_000' do
      expect(config.max_turns_per_transcript).to eq(1_000)
    end

    it 'sets strip_file_contents to true' do
      expect(config.strip_file_contents).to be(true)
    end

    it 'sets strip_absolute_paths to true' do
      expect(config.strip_absolute_paths).to be(true)
    end

    it 'sets custom_patterns to empty array' do
      expect(config.custom_patterns).to eq([])
    end

    it 'sets intent_confidence_threshold to 0.5' do
      expect(config.intent_confidence_threshold).to eq(0.5)
    end
  end

  describe '#redaction_marker=' do
    it 'accepts a valid string' do
      config.redaction_marker = '***'
      expect(config.redaction_marker).to eq('***')
    end

    it 'raises ConfigurationError for empty string' do
      expect { config.redaction_marker = '' }
        .to raise_error(WildTranscriptPipeline::ConfigurationError)
    end

    it 'raises ConfigurationError for whitespace-only string' do
      expect { config.redaction_marker = '   ' }
        .to raise_error(WildTranscriptPipeline::ConfigurationError)
    end

    it 'raises ConfigurationError for non-string' do
      expect { config.redaction_marker = 42 }
        .to raise_error(WildTranscriptPipeline::ConfigurationError)
    end
  end

  describe '#max_turn_content_length=' do
    it 'accepts a positive integer' do
      config.max_turn_content_length = 500
      expect(config.max_turn_content_length).to eq(500)
    end

    it 'raises ConfigurationError for zero' do
      expect { config.max_turn_content_length = 0 }
        .to raise_error(WildTranscriptPipeline::ConfigurationError)
    end

    it 'raises ConfigurationError for negative integer' do
      expect { config.max_turn_content_length = -1 }
        .to raise_error(WildTranscriptPipeline::ConfigurationError)
    end

    it 'raises ConfigurationError for float' do
      expect { config.max_turn_content_length = 500.5 }
        .to raise_error(WildTranscriptPipeline::ConfigurationError)
    end
  end

  describe '#max_turns_per_transcript=' do
    it 'accepts a positive integer' do
      config.max_turns_per_transcript = 200
      expect(config.max_turns_per_transcript).to eq(200)
    end

    it 'raises ConfigurationError for zero' do
      expect { config.max_turns_per_transcript = 0 }
        .to raise_error(WildTranscriptPipeline::ConfigurationError)
    end
  end

  describe '#strip_file_contents=' do
    it 'accepts true' do
      config.strip_file_contents = true
      expect(config.strip_file_contents).to be(true)
    end

    it 'accepts false' do
      config.strip_file_contents = false
      expect(config.strip_file_contents).to be(false)
    end

    it 'raises ConfigurationError for non-boolean' do
      expect { config.strip_file_contents = 'yes' }
        .to raise_error(WildTranscriptPipeline::ConfigurationError)
    end
  end

  describe '#strip_absolute_paths=' do
    it 'accepts false' do
      config.strip_absolute_paths = false
      expect(config.strip_absolute_paths).to be(false)
    end

    it 'raises ConfigurationError for nil' do
      expect { config.strip_absolute_paths = nil }
        .to raise_error(WildTranscriptPipeline::ConfigurationError)
    end
  end

  describe '#custom_patterns=' do
    it 'accepts an array of Regexp' do
      config.custom_patterns = [/secret/i]
      expect(config.custom_patterns).to eq([/secret/i])
    end

    it 'accepts an empty array' do
      config.custom_patterns = []
      expect(config.custom_patterns).to eq([])
    end

    it 'raises ConfigurationError for non-Array' do
      expect { config.custom_patterns = /secret/ }
        .to raise_error(WildTranscriptPipeline::ConfigurationError)
    end

    it 'raises ConfigurationError when array contains non-Regexp' do
      expect { config.custom_patterns = ['not a regexp'] }
        .to raise_error(WildTranscriptPipeline::ConfigurationError)
    end
  end

  describe '#intent_confidence_threshold=' do
    it 'accepts a float between 0 and 1' do
      config.intent_confidence_threshold = 0.7
      expect(config.intent_confidence_threshold).to eq(0.7)
    end

    it 'accepts 0.0' do
      config.intent_confidence_threshold = 0.0
      expect(config.intent_confidence_threshold).to eq(0.0)
    end

    it 'accepts 1.0' do
      config.intent_confidence_threshold = 1.0
      expect(config.intent_confidence_threshold).to eq(1.0)
    end

    it 'raises ConfigurationError for value above 1.0' do
      expect { config.intent_confidence_threshold = 1.1 }
        .to raise_error(WildTranscriptPipeline::ConfigurationError)
    end

    it 'raises ConfigurationError for negative value' do
      expect { config.intent_confidence_threshold = -0.1 }
        .to raise_error(WildTranscriptPipeline::ConfigurationError)
    end
  end

  describe '#freeze!' do
    it 'freezes the configuration' do
      config.freeze!
      expect(config).to be_frozen
    end

    it 'prevents further modification after freeze' do
      config.freeze!
      expect { config.redaction_marker = '***' }.to raise_error(FrozenError)
    end

    it 'freezes custom_patterns' do
      config.custom_patterns = [/foo/]
      config.freeze!
      expect(config.custom_patterns).to be_frozen
    end
  end
end
