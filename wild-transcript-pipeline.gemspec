# frozen_string_literal: true

require_relative 'lib/wild_transcript_pipeline/version'

Gem::Specification.new do |spec|
  spec.name = 'wild-transcript-pipeline'
  spec.version = WildTranscriptPipeline::VERSION
  spec.authors = ['Intent Solutions']
  spec.summary = 'Ingest, normalize, strip, and export AI agent conversation transcripts'
  spec.description = 'Library for ingesting conversation transcripts from AI agent sessions, ' \
                     'normalizing into a structured schema, stripping sensitive content, ' \
                     'and exporting clean data for downstream consumers such as gap-miner.'
  spec.homepage = 'https://github.com/jeremylongshore/wild-transcript-pipeline'
  spec.license = 'Nonstandard'
  spec.required_ruby_version = '>= 3.2.0'

  spec.files = Dir['lib/**/*.rb', 'LICENSE', 'README.md']
  spec.require_paths = ['lib']

  spec.metadata['rubygems_mfa_required'] = 'true'
end
