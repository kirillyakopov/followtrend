#
#  add_widget_target.rb
#  followtrend
#
#  Ruby script using the 'xcodeproj' gem to add a Widget Extension target
#  to the Xcode project, configuring code compiling, entitlements, product name,
#  and synchronized group exceptions.
#

require 'xcodeproj'

project_path = 'followtrend.xcodeproj'
project = Xcodeproj::Project.open(project_path)

# 1. Main Target & App Group configuration
main_target = project.targets.find { |t| t.name == 'followtrend' }
unless main_target
  puts "Error: Main target 'followtrend' not found!"
  exit 1
end

# Add entitlements to main target build configurations
main_target.build_configurations.each do |config|
  config.build_settings['CODE_SIGN_ENTITLEMENTS'] = 'followtrend/followtrend.entitlements'
end

# Check if target already exists and delete to avoid duplicate config on rerun
existing_widget = project.targets.find { |t| t.name == 'PortfolioWidget' }
if existing_widget
  puts "PortfolioWidget target already exists. Re-configuring target..."
  project.targets.delete(existing_widget)
end

# Clean up any dangling target dependencies
main_target.dependencies.delete_if do |dep|
  is_dangling = dep.target.nil? || dep.target.name == 'PortfolioWidget'
  puts "Removing target dependency: #{dep.target&.name || 'nil'} (GUID: #{dep.target&.uuid})" if is_dangling
  is_dangling
end

# Clean up any copy files build phases references to deleted products (.appex)
main_target.copy_files_build_phases.each do |phase|
  phase.files.delete_if do |file|
    is_dangling = file.file_ref.nil? || (file.file_ref.respond_to?(:path) && file.file_ref.path.end_with?('.appex'))
    puts "Removing copy files entry: #{file.file_ref&.path || 'nil'}" if is_dangling
    is_dangling
  end
end


# 2. Create the Widget Target
# Using app_extension type
widget_target = project.new_target(:app_extension, 'PortfolioWidget', :ios, '17.0')


# Configure build settings for widget target
widget_target.build_configurations.each do |config|
  config.build_settings['PRODUCT_NAME'] = 'PortfolioWidget'
  config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.followtrend.PortfolioWidget'
  config.build_settings['CODE_SIGN_ENTITLEMENTS'] = 'followtrend/Widgets/PortfolioWidget.entitlements'
  config.build_settings['INFOPLIST_FILE'] = 'followtrend/Widgets/Info.plist'
  config.build_settings['GENERATE_INFOPLIST_FILE'] = 'YES'
  config.build_settings['SKIP_INSTALL'] = 'YES'
  config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '17.0'
  config.build_settings['LD_RUNPATH_SEARCH_PATHS'] = '$(inherited) @executable_path/Frameworks @executable_path/../../Frameworks'
  config.build_settings['SWIFT_VERSION'] = '5.0'
  config.build_settings['CODE_SIGN_STYLE'] = 'Automatic'
  config.build_settings['DEVELOPMENT_TEAM'] = ''
  config.build_settings['CURRENT_PROJECT_VERSION'] = '1'
  config.build_settings['MARKETING_VERSION'] = '1.0'
end

# Remove default folder Xcodeproj created in project layout
default_widget_group = project.main_group.groups.find { |g| g.name == 'PortfolioWidget' }
default_widget_group.remove_from_project if default_widget_group

# Create logical Groups inside followtrend
main_group = project.main_group.groups.find { |g| g.name == 'followtrend' } || project.main_group

# Find or create Shared group and link PortfolioStore
shared_group = main_group.groups.find { |g| g.name == 'Shared' } || main_group.new_group('Shared')
shared_ref = shared_group.files.find { |f| f.path == 'followtrend/Shared/PortfolioStore.swift' } || 
             shared_group.new_file('followtrend/Shared/PortfolioStore.swift')

# Add Shared code reference to widget compilation list
widget_target.source_build_phase.add_file_reference(shared_ref)

# Find or create Widgets group
widgets_group = main_group.groups.find { |g| g.name == 'Widgets' } || main_group.new_group('Widgets')

widget_sources = [
  'followtrend/Widgets/PortfolioWidget.swift',
  'followtrend/Widgets/PortfolioProvider.swift',
  'followtrend/Widgets/PortfolioEntry.swift',
  'followtrend/Widgets/WidgetView.swift',
  'followtrend/Widgets/WidgetDesignExtensions.swift'
]

widget_sources.each do |file_path|
  file_ref = widgets_group.files.find { |f| f.path == file_path } || widgets_group.new_file(file_path)
  widget_target.source_build_phase.add_file_reference(file_ref)
end

# Add configuration templates to visual groups
widgets_group.new_file('followtrend/Widgets/Info.plist') unless widgets_group.files.any? { |f| f.path == 'followtrend/Widgets/Info.plist' }
widgets_group.new_file('followtrend/Widgets/PortfolioWidget.entitlements') unless widgets_group.files.any? { |f| f.path == 'followtrend/Widgets/PortfolioWidget.entitlements' }

# 3. Add Dependency & Copy Files phase to compile widget and embed it into app bundle
dependency = project.new(Xcodeproj::Project::Object::PBXTargetDependency)
dependency.target = widget_target
main_target.dependencies << dependency

# Add or find copy files phase spec for App Extensions (PlugIns directory is dest 13)
embed_phase = main_target.copy_files_build_phases.find { |p| p.name == 'Embed App Extensions' } || 
              main_target.new_copy_files_build_phase('Embed App Extensions')
embed_phase.symbol_dst_subfolder_spec = :plug_ins

# Map widget's compiled appex product inside copy phase
build_file = embed_phase.add_file_reference(widget_target.product_reference)
build_file.settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy', 'CodeSignOnCopy'] }

# 4. Clean up main target manual compiles and exceptions for synchronized root group
main_target.source_build_phase.files.each do |f|
  if f.file_ref && f.file_ref.path && (f.file_ref.path.end_with?('PortfolioStore.swift') || f.file_ref.path.end_with?('DesignSystem.swift'))
    puts "Removing manual build file reference for #{f.file_ref.path} from main target"
    main_target.source_build_phase.remove_build_file(f)
  end
end

# Rebuild exceptions set for the synchronized folder "followtrend"
exc = project.objects.find { |o| o.isa == 'PBXFileSystemSynchronizedBuildFileExceptionSet' && o.target.uuid == main_target.uuid }
if exc
  puts "Updating synchronized build file exceptions..."
  # Clean up old exceptions and only include target widget files + info/entitlements
  # Note: PortfolioStore.swift and DesignSystem.swift should NOT be exceptions so they get compiled by the main target automatically.
  exceptions_list = [
    "Info.plist",
    "Widgets/Info.plist",
    "Widgets/PortfolioWidget.swift",
    "Widgets/PortfolioProvider.swift",
    "Widgets/PortfolioEntry.swift",
    "Widgets/WidgetView.swift",
    "Widgets/WidgetDesignExtensions.swift",
    "Widgets/PortfolioWidget.entitlements"
  ]
  exc.membership_exceptions = exceptions_list
  puts "Updated exception set to: #{exc.membership_exceptions.inspect}"
end

# Save Project Changes
project.save
puts "Successfully configured Xcode project targets for Widget Extension!"
