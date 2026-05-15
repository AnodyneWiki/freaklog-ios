#!/usr/bin/env ruby
require 'xcodeproj'

project_path = 'FreakLog.xcodeproj'
project = Xcodeproj::Project.open(project_path)

WATCH_TARGET = 'FreakLogWatch'
WIDGET_TARGET = 'FreakLogWatchWidgets'
IOS_TARGET = 'FreakLog'
WATCH_BUNDLE_ID = 'woof.freaklog.watchkitapp'
WIDGET_BUNDLE_ID = 'woof.freaklog.watchkitapp.widgets'
WATCH_DEPLOY = '10.0'

ios_target = project.targets.find { |t| t.name == IOS_TARGET }
abort "iOS target missing" unless ios_target

[WATCH_TARGET, WIDGET_TARGET].each do |name|
  if (existing = project.targets.find { |t| t.name == name })
    puts "Removing existing target #{name}"
    # Remove product reference from any embed phases
    pr = existing.product_reference
    if pr
      project.targets.each do |t|
        t.copy_files_build_phases.each do |phase|
          phase.files.dup.each do |bf|
            phase.remove_build_file(bf) if bf.file_ref == pr
          end
        end
        # Remove dependencies
        t.dependencies.dup.each do |dep|
          t.dependencies.delete(dep) if dep.target == existing
        end
      end
    end
    project.targets.delete(existing)
  end
end

# Clean up any orphaned build files in embed phases
project.targets.each do |t|
  t.copy_files_build_phases.each do |phase|
    phase.files.dup.each do |bf|
      if bf.file_ref.nil? || (bf.file_ref.respond_to?(:path) && bf.file_ref.path.nil?)
        phase.remove_build_file(bf)
      end
    end
  end
end

%w[FreakLogWatch FreakLogWatchWidgets].each do |g|
  grp = project.main_group.children.find { |c| c.respond_to?(:display_name) && c.display_name == g }
  grp.remove_from_project if grp
end

puts "Creating watch app target"
watch_target = project.new_target(:application, WATCH_TARGET, :watchos, WATCH_DEPLOY, nil, :swift)

puts "Creating widget target"
widget_target = project.new_target(:app_extension, WIDGET_TARGET, :watchos, WATCH_DEPLOY, nil, :swift)

def configure_target(target, bundle_id, deploy, info_plist, entitlements, is_widget: false)
  target.build_configurations.each do |config|
    bs = config.build_settings
    bs['PRODUCT_BUNDLE_IDENTIFIER'] = bundle_id
    bs['WATCHOS_DEPLOYMENT_TARGET'] = deploy
    bs['SDKROOT'] = 'watchos'
    bs['TARGETED_DEVICE_FAMILY'] = '4'
    bs['SUPPORTED_PLATFORMS'] = 'watchsimulator watchos'
    bs['INFOPLIST_FILE'] = info_plist
    bs['CODE_SIGN_ENTITLEMENTS'] = entitlements
    bs['CODE_SIGN_STYLE'] = 'Automatic'
    bs['CURRENT_PROJECT_VERSION'] = '1'
    bs['MARKETING_VERSION'] = '1.0'
    bs['SWIFT_VERSION'] = '5.0'
    bs['ENABLE_PREVIEWS'] = 'YES'
    bs['GENERATE_INFOPLIST_FILE'] = 'NO'
    bs['ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME'] = 'AccentColor'
    bs['ASSETCATALOG_COMPILER_APPICON_NAME'] = 'AppIcon'
    bs['DEVELOPMENT_TEAM'] = ''
    bs['PRODUCT_NAME'] = '$(TARGET_NAME)'
    bs['SKIP_INSTALL'] = is_widget ? 'YES' : 'NO'
  end
end

configure_target(watch_target, WATCH_BUNDLE_ID, WATCH_DEPLOY,
                 'FreakLogWatch/Info.plist', 'FreakLogWatch/FreakLogWatch.entitlements')
configure_target(widget_target, WIDGET_BUNDLE_ID, WATCH_DEPLOY,
                 'FreakLogWatchWidgets/Info.plist', 'FreakLogWatchWidgets/FreakLogWatchWidgets.entitlements',
                 is_widget: true)

watch_group = project.main_group.new_group('FreakLogWatch', 'FreakLogWatch')
widget_group = project.main_group.new_group('FreakLogWatchWidgets', 'FreakLogWatchWidgets')

require 'find'
watch_swift = []
Find.find('FreakLogWatch') do |path|
  next if File.directory?(path)
  next unless path.end_with?('.swift')
  watch_swift << path
end
puts "Watch swift files: #{watch_swift.size}"

widget_swift = Dir.glob('FreakLogWatchWidgets/*.swift')
puts "Widget swift files: #{widget_swift.size}"

def add_path(group, abs_path)
  ref = group.new_reference(File.expand_path(abs_path))
  ref.path = abs_path
  ref.source_tree = 'SOURCE_ROOT'
  ref.name = File.basename(abs_path)
  ref
end

sub_groups = {}
watch_swift.each do |sf|
  rel_under = sf.sub(%r{^FreakLogWatch/}, '')
  parts = rel_under.split('/')
  group = watch_group
  if parts.length > 1
    parts[0..-2].each do |p|
      key = group.path.to_s + '/' + p
      group = (sub_groups[key] ||= group.new_group(p, p))
    end
  end
  ref = add_path(group, sf)
  watch_target.add_file_references([ref])
end

widget_swift.each do |sf|
  ref = add_path(widget_group, sf)
  widget_target.add_file_references([ref])
end

# Resources
sub_json = 'FreakLog/Assets/substances.json'
sub_ref = watch_group.new_reference(File.expand_path(sub_json))
sub_ref.path = sub_json
sub_ref.source_tree = 'SOURCE_ROOT'
sub_ref.name = 'substances.json'
watch_target.add_resources([sub_ref])
widget_target.add_resources([sub_ref])

watch_assets = 'FreakLogWatch/Assets.xcassets'
wa_ref = watch_group.new_reference(File.expand_path(watch_assets))
wa_ref.path = watch_assets
wa_ref.source_tree = 'SOURCE_ROOT'
wa_ref.name = 'Assets.xcassets'
wa_ref.last_known_file_type = 'folder.assetcatalog'
watch_target.add_resources([wa_ref])

# Core Data model: find existing reference (it's an XCVersionGroup, not a regular file ref)
existing_model = project.objects.select { |o| o.isa == 'XCVersionGroup' }.find { |o| o.path && o.path.end_with?('Main.xcdatamodeld') }
existing_model ||= project.files.find { |f| f.path && f.path.end_with?('Main.xcdatamodeld') }
if existing_model
  puts "Reusing model ref: #{existing_model.path} (#{existing_model.isa})"
  # Add to Sources so class generation happens; the mom file auto-bundles
  watch_target.source_build_phase.add_file_reference(existing_model)
  widget_target.source_build_phase.add_file_reference(existing_model)
else
  abort "ERROR: no Main.xcdatamodeld file ref found"
end

EXCLUDE_FROM_WATCH = [
  'FreakLog/AppDelegate.swift',
  'FreakLog/App Intents/AppIntents.swift',
  'FreakLog/Main/ActivityManager.swift',
  'FreakLog/Main/Content/ContentView.swift',
  'FreakLog/Add Ingestion/Choose Substance/ChooseSubstanceScreen.swift',
  'FreakLog/Add Ingestion/Choose Substance/Components/CustomSubstanceSuggestionView.swift',
  'FreakLog/Add Ingestion/Dose/MDMA Dose/MDMAOptimalDoseSection.swift',
  'FreakLog/Add Ingestion/Finish/Other/Choose Location/ChooseLocationScreenContent.swift',
  'FreakLog/Journal/JournalCalendarScreen.swift',
  'FreakLog/Journal/calendar/DayView.swift',
  'FreakLog/Journal/Other/Experience/Components/LiveActivityButton.swift',
  'FreakLog/Journal/Other/Experience/Components/Location/EditLocationLinkAndMap.swift',
  'FreakLog/Journal/Other/Experience/ExperienceScreen.swift',
  'FreakLog/Search/SearchScreen.swift',
  'FreakLog/Search/Substance/Web/WebViewRepresentable.swift',
  'FreakLog/Settings/SettingsScreen.swift',
  'FreakLog/Settings/Components/Custom Units/CustomUnitsChooseSubstanceScreen.swift',
  'FreakLog/Stats/Experience Charts/DailyExperienceChart.swift',
  'FreakLog/Stats/Experience Charts/ExperienceDetailsScreen.swift',
  'FreakLog/Stats/Experience Charts/ExperienceOverview.swift',
  'FreakLog/Stats/Experience Charts/MonthlyExperienceChart.swift',
  'FreakLog/Stats/Experience Charts/YearlyExperienceChart.swift',
  'FreakLog/Stats/StatsScreen.swift',
  'FreakLog/Stats/Substance Charts/Dosage Charts/ChartScrollingHelper.swift',
  'FreakLog/Stats/Substance Charts/Dosage Charts/DosageStatChart.swift',
  'FreakLog/Stats/Substance Charts/Dosage Charts/DosageStatScreen.swift',
  'FreakLog/Stats/Substance Charts/SubstanceDetailsScreen.swift',
  'FreakLog/Stats/Substance Charts/SubstanceOverview.swift',
  'FreakLog/Stats/Tolerance/Screen/ToleranceChart.swift',
  'FreakLog/Stats/Tolerance/ToleranceChartOverView.swift',
  'FreakLog/FreakLog.swift',
  'FreakLog/Search/Substance/Section Screens/CategorySection.swift',
  'FreakLog/Search/SearchSubstanceRow.swift',
  'FreakLog/Add Ingestion/Choose Substance/Components/PureSubstanceSuggestionView.swift',
  'FreakLog/Add Ingestion/Choose Substance/Components/CustomUnitSuggestionView.swift',
  'FreakLog/Add Ingestion/Choose Substance/ChooseSubstance-ViewModel.swift',
  'FreakLog/Add Ingestion/Finish/FinishIngestionScreen.swift',
  'FreakLog/Journal/Other/Experience/Components/ExperienceToolbarContent.swift',
  'FreakLog/Safer/Spray/SprayCalculatorScreen.swift',
  'FreakLog/Settings/Codables/JournalFile.swift',
  'FreakLog/Settings/Settings-ViewModel.swift',
  'FreakLog/Stats/Tolerance/Add Tolerance Ingestion/AddToleranceIngestionScreen.swift',
  'FreakLog/Safer/Spray/SprayCalculatorScreen-ViewModel.swift',
  'FreakLog/Journal/All Ingestions/ViewModels/AllIngestionsViewModel.swift',
  'FreakLog/Journal/All Ingestions/Views/AllIngestionsView.swift',
  'FreakLog/Journal/JournalScreen.swift',
  'FreakLog/Main/LockScreen.swift',
  'FreakLog/Main/Navigation/GetScreen.swift',
  'FreakLog/Add Ingestion/Route/ChooseRouteScreen.swift',
  'FreakLog/Add Ingestion/Route/RouteBox.swift',
  'FreakLog/Add Ingestion/Route/custom/CustomSubstanceChooseRouteScreen.swift',
  'FreakLog/Settings/WebhookPresetEditScreen.swift',
  'FreakLog/Settings/WebhooksScreen.swift',
  'FreakLog/Stats/TimeRange/TimeRangePicker.swift',
  'FreakLog/Stats/Tolerance/Add Tolerance Ingestion/Choose Date And Color/ChooseDateScreenContent.swift',
  'FreakLog/Stats/Tolerance/Screen/ToleranceChartScreen.swift',
  'FreakLog/Stats/Tolerance/Screen/ToleranceChartScreenContent.swift',
  'FreakLog/Add Ingestion/Route/ChooseOtherRouteScreen.swift',
  'FreakLog/Stats/Tolerance/Add Tolerance Ingestion/Choose Date And Color/ChooseDateScreen.swift',
  'FreakLog/Settings/FAQ/FAQView.swift',
  'FreakLog/Journal/Other/Experience/Components/Rating/EditRatingScreen.swift',
  'FreakLog/Journal/Other/Experience/Components/Timed Note/TimedNoteScreenContent.swift',
  'FreakLog/Journal/Other/Experience/Components/TimelineScreen.swift',
  'FreakLog/Journal/Other/Experience/DynamicExperienceScreen.swift',
  'FreakLog/Journal/Other/ExperienceRow/ExperienceRow.swift',
  'FreakLog/Main/AuthenticatorWrapper.swift',
  'FreakLog/Add Ingestion/Custom Units/CustomUnitDosePicker.swift',
  'FreakLog/Add Ingestion/Custom Units/CustomUnitsChooseDoseScreen.swift',
  'FreakLog/Add Ingestion/Dose/ChooseDoseScreen.swift',
  'FreakLog/Add Ingestion/Dose/MDMA Dose/ChooseMDMADoseScreen.swift',
  'FreakLog/Add Ingestion/Dose/MDMA Dose/MDMAMaxDoseCalculator.swift',
  'FreakLog/Add Ingestion/Dose/custom/CustomSubstanceChooseDoseScreen.swift',
  'FreakLog/Add Ingestion/Finish/Other/Choose Location/ChooseLocationScreen.swift',
  'FreakLog/Add Ingestion/Finish/Other/EditConsumerScreen.swift',
  'FreakLog/Add Ingestion/Finish/Other/ExperienceTitleScreen.swift',
  'FreakLog/Add Ingestion/Finish/Other/Ingestion Note/IngestionNoteScreen.swift',
  'FreakLog/Add Ingestion/Finish/TimePointOrRangePicker.swift',
  'FreakLog/Add Ingestion/Finish/Other/Ingestion Note/IngestionNote-ViewModel.swift',
  'FreakLog/Journal/Other/Experience/Components/Edit Ingestion/EditIngestionScreen.swift',
  'FreakLog/Journal/ExperiencesList.swift',
  'FreakLog/Journal/Other/Experience/Components/Edit Ingestion/DosePicker.swift',
  'FreakLog/Journal/Other/Experience/Components/EditNotesScreen.swift',
  'FreakLog/Journal/Other/Experience/Components/EditTitleScreen.swift',
  'FreakLog/Journal/Other/Experience/Components/Ingestion/IngestionRow.swift',
  'FreakLog/Journal/Other/Experience/Components/Location/AddLocationScreen.swift',
  'FreakLog/Journal/Other/Experience/Components/Location/EditLocationScreen.swift',
  'FreakLog/Add Ingestion/Dose/UnitsPicker.swift',
  'FreakLog/Settings/Components/Custom Units/CustomUnitsScreen.swift',
  'FreakLog/Settings/Components/Custom Units/EditCustomUnitsScreen.swift',
  'FreakLog/Settings/Components/Custom Units/FinishCustomUnitsScreen.swift',
  'FreakLog/Settings/Components/Custom Units/CustomUnitsArchiveScreen.swift',
  'FreakLog/Safer/Spray/AddSprayScreen.swift',
  'FreakLog/Search/Custom Substance/AddCustomSubstanceView.swift',
  'FreakLog/Search/Custom Substance/AddCustomSubstance-ViewModel.swift',
  'FreakLog/Journal/Other/Experience/Components/Timed Note/AddTimedNoteScreen.swift',
  'FreakLog/Journal/Other/Experience/Components/Timed Note/EditTimedNoteScreen.swift',
  'FreakLog/Journal/Other/Experience/Components/TimelineSection.swift',
  'FreakLog/Journal/Other/Experience/Components/Rating/ShulginRatingSection.swift',
  'FreakLog/Search/Substance/Section Screens/DosesSection.swift',
  'FreakLog/Search/Substance/SubstanceScreen.swift',
  'FreakLog/Search/Substance/Web/WebViewScreen.swift',
  'FreakLog/Search/SubstanceSearchBarWithFilter.swift',
]

SHARED_FILES = Dir.glob('FreakLog/**/*.swift').reject do |f|
  EXCLUDE_FROM_WATCH.include?(f) || f.start_with?('FreakLog/Preview Content/')
end.sort

added = 0
missing = []
SHARED_FILES.each do |path|
  unless File.exist?(path)
    missing << path
    next
  end
  base = File.basename(path)
  ref = project.files.find { |f| f.path == path }
  ref ||= project.files.find { |f| f.path && f.path.end_with?('/' + base) }
  ref ||= project.files.find { |f| f.real_path.to_s == File.expand_path(path) }
  unless ref
    puts "WARN: no file ref for #{path}"
    next
  end
  watch_target.add_file_references([ref])
  widget_target.add_file_references([ref])
  added += 1
end
puts "Shared files added: #{added}, missing files: #{missing.size}"
missing.each { |m| puts "  MISSING #{m}" }

# Embed widget into watch app
embed_widgets = watch_target.new_copy_files_build_phase('Embed Foundation Extensions')
embed_widgets.symbol_dst_subfolder_spec = :plug_ins
ebf = embed_widgets.add_file_reference(widget_target.product_reference)
ebf.settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }
watch_target.add_dependency(widget_target)

# Embed watch app into iOS via existing phase
embed_watch_phase = ios_target.copy_files_build_phases.find { |p| p.name == 'Embed Watch Content' }
if embed_watch_phase
  ebf2 = embed_watch_phase.add_file_reference(watch_target.product_reference)
  ebf2.settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }
  ios_target.add_dependency(watch_target)
  puts "Embedded watch app into iOS app"
end

project.save
puts "DONE"
project.targets.each { |t| puts "  #{t.name}" }
