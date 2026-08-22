#!/usr/bin/env ruby
# frozen_string_literal: true

require 'xcodeproj'

ios_dir = File.expand_path('../../apps/flutter/ios', __dir__)
project = Xcodeproj::Project.open(File.join(ios_dir, 'Runner.xcodeproj'))
runner = project.targets.find { |target| target.name == 'Runner' }
abort 'Runner target not found' unless runner

def file_reference(group, path)
  group.files.find { |file| file.path == path } || group.new_file(path)
end

runner_group = project.main_group.find_subpath('Runner', true)
shared_group = project.main_group.find_subpath('Shared', true)
widgets_group = project.main_group.find_subpath('QingxuWidgets', true)

bridge = file_reference(runner_group, 'IOSSystemFeaturesBridge.swift')
attributes = file_reference(shared_group, 'QingxuPomodoroAttributes.swift')
runner.add_file_references([bridge, attributes])

widgets = project.targets.find { |target| target.name == 'QingxuWidgets' }
widgets ||= project.new_target(:app_extension, 'QingxuWidgets', :ios, '16.2')
widget_source = file_reference(widgets_group, 'QingxuWidgets.swift')
widgets.add_file_references([widget_source, attributes])

widgets.build_configurations.each do |configuration|
  settings = configuration.build_settings
  settings['APPLICATION_EXTENSION_API_ONLY'] = 'YES'
  settings['CODE_SIGN_ENTITLEMENTS'] = 'QingxuWidgets/QingxuWidgets.entitlements'
  settings['CURRENT_PROJECT_VERSION'] = '$(FLUTTER_BUILD_NUMBER)'
  settings['GENERATE_INFOPLIST_FILE'] = 'NO'
  settings['INFOPLIST_FILE'] = 'QingxuWidgets/Info.plist'
  settings['IPHONEOS_DEPLOYMENT_TARGET'] = '16.2'
  settings['MARKETING_VERSION'] = '$(FLUTTER_BUILD_NAME)'
  settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'one.darker.qingxu.widgets'
  settings['PRODUCT_NAME'] = '$(TARGET_NAME)'
  settings['SKIP_INSTALL'] = 'YES'
  settings['SWIFT_VERSION'] = '5.0'
  settings['TARGETED_DEVICE_FAMILY'] = '1,2'
end

runner.build_configurations.each do |configuration|
  configuration.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '16.2'
end

unless runner.dependencies.any? { |dependency| dependency.target == widgets }
  runner.add_dependency(widgets)
end

embed_phase = runner.copy_files_build_phases.find { |phase| phase.name == 'Embed App Extensions' }
embed_phase ||= runner.new_copy_files_build_phase('Embed App Extensions')
embed_phase.dst_subfolder_spec = '13'
unless embed_phase.files_references.include?(widgets.product_reference)
  build_file = embed_phase.add_file_reference(widgets.product_reference, true)
  build_file.settings = { 'ATTRIBUTES' => %w[RemoveHeadersOnCopy CodeSignOnCopy] }
end

project.save
puts 'Configured QingxuWidgets and Live Activity targets.'
