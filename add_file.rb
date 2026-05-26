require 'xcodeproj'
project_path = 'followtrend.xcodeproj'
project = Xcodeproj::Project.open(project_path)
target = project.targets.first

group = project.main_group.groups.find { |g| g.name == 'followtrend' } || project.main_group
services_group = group.groups.find { |g| g.name == 'Services' } || group.new_group('Services')

file_ref = services_group.new_file('followtrend/Services/AppLanguageManager.swift')
target.source_build_phase.add_file_reference(file_ref)
project.save
