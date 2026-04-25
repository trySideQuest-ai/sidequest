#!/usr/bin/env ruby
# sync-target-files.rb - Add missing Swift sources and test target to Xcode project
# Usage: ruby sync-target-files.rb

require 'xcodeproj'
require 'pathname'

# Configuration
PROJECT_PATH = 'SideQuestApp.xcodeproj'
MAIN_TARGET_NAME = 'SideQuestApp'
TEST_TARGET_NAME = 'SideQuestAppTests'
APP_MAIN_BUNDLE_ID = 'ai.sidequest.app'
TEST_BUNDLE_ID = 'ai.sidequest.appTests'

# Paths
BASE_DIR = Pathname.new(Dir.pwd)
MODELS_DIR = BASE_DIR + 'SideQuestApp/Models'
TESTS_DIR = BASE_DIR + 'SideQuestAppTests'

# Files to add to main target
MAIN_TARGET_FILES = [
  'SideQuestApp/Models/WordPieceTokenizer.swift',
  'SideQuestApp/Models/EmbeddingModel.swift',
  'SideQuestApp/Models/EmbeddingService.swift',
  'SideQuestApp/Models/EmbeddingInference.swift'
]

# Files to add to test target
TEST_TARGET_FILES = [
  'SideQuestAppTests/TokenizerTests.swift',
  'SideQuestAppTests/ModelFetchTests.swift',
  'SideQuestAppTests/InferenceTests.swift',
  'SideQuestAppTests/EmbedParityTests.swift'
]

def file_exists?(path)
  File.exist?(path)
end

def add_files_to_target(project, target, file_paths)
  target_group = project.main_group
  added_count = 0

  file_paths.each do |file_path|
    unless file_exists?(file_path)
      puts "WARNING: File not found on disk: #{file_path}"
      next
    end

    # Check if file is already in target
    existing_files = target.source_build_phase.files.map { |f| f.file_ref.real_path.to_s rescue nil }.compact
    file_real_path = File.expand_path(file_path)

    if existing_files.include?(file_real_path)
      puts "SKIP: #{file_path} already in #{target.name}"
      next
    end

    # Add file to project (if not already there)
    file_ref = target_group[file_path]
    unless file_ref
      file_ref = target_group.new_file(file_path)
      puts "NEW:  Added file reference: #{file_path}"
    end

    # Add to target's sources build phase
    target.source_build_phase.add_file_reference(file_ref)
    puts "ADD:  Added to #{target.name} sources: #{file_path}"
    added_count += 1
  end

  added_count
end

def create_test_target(project, host_target)
  # Check if test target already exists
  existing_test_target = project.targets.find { |t| t.name == TEST_TARGET_NAME }
  return existing_test_target if existing_test_target

  puts "CREATE: Creating test target #{TEST_TARGET_NAME}..."

  # Create test target
  test_target = project.new_target(
    :unit_test_bundle,
    TEST_TARGET_NAME,
    :macos
  )

  # Configure build settings
  test_target.build_configurations.each do |config|
    config.build_settings['PRODUCT_NAME'] = TEST_TARGET_NAME
    config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = TEST_BUNDLE_ID
    config.build_settings['TEST_HOST'] = "$(BUILT_PRODUCTS_DIR)/#{host_target.name}.app/Contents/MacOS/#{host_target.name}"
    config.build_settings['BUNDLE_LOADER'] = "$(TEST_HOST)"
  end

  puts "CREATE: Test target created with host: #{host_target.name}"

  test_target
end

def create_test_scheme(project, test_target)
  scheme_name = TEST_TARGET_NAME

  # Check if scheme exists
  schemes_dir = project.path + 'xcshareddata/xcschemes'
  scheme_path = schemes_dir + "#{scheme_name}.xcscheme"

  return if File.exist?(scheme_path)

  # Create basic scheme via command-line tool (xcodeproj doesn't have great scheme support)
  puts "SCHEME: Scheme #{scheme_name} will be auto-created by Xcode on first build"
end

def main
  puts "=== Syncing Swift files to Xcode project ==="
  puts "Project: #{PROJECT_PATH}"

  # Open project
  unless File.directory?(PROJECT_PATH)
    puts "ERROR: Project not found at #{PROJECT_PATH}"
    exit 1
  end

  project = Xcodeproj::Project.open(PROJECT_PATH)

  # Get main target
  main_target = project.targets.find { |t| t.name == MAIN_TARGET_NAME }
  unless main_target
    puts "ERROR: Target #{MAIN_TARGET_NAME} not found"
    exit 1
  end

  puts "\n--- Adding sources to #{MAIN_TARGET_NAME} ---"
  main_count = add_files_to_target(project, main_target, MAIN_TARGET_FILES)

  puts "\n--- Creating/updating test target ---"
  test_target = create_test_target(project, main_target)

  puts "\n--- Adding test sources to #{TEST_TARGET_NAME} ---"
  test_count = add_files_to_target(project, test_target, TEST_TARGET_FILES)

  puts "\n--- Creating test scheme ---"
  create_test_scheme(project, test_target)

  # Save project
  puts "\nSaving project..."
  project.save

  puts "\n=== Summary ==="
  puts "Files added to #{MAIN_TARGET_NAME}: #{main_count}"
  puts "Files added to #{TEST_TARGET_NAME}: #{test_count}"
  puts "Test target: #{TEST_TARGET_NAME} (host: #{MAIN_TARGET_NAME})"
  puts "\nDone! Run 'xcodebuild -list' to verify targets/schemes."
end

main
