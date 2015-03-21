require "FileUtils"

module CocoapodsPruneLocalizations
  class Pruner
    def initialize(context, user_options)
      @pod_project = Xcodeproj::Project.open File.join(context.sandbox_root, 'Pods.xcodeproj')
      @user_options = user_options
      @pruned_bundles_path = File.join(context.sandbox_root, "Pruned Localized Bundles")
      FileUtils.mkdir @pruned_bundles_path unless Dir.exist? @pruned_bundles_path
    end
    
    def prune!
      langs_to_keep = @user_options["localizations"] || []
      Pod::UI.section 'Pruning unused localizations' do
        pod_groups = @pod_project["Pods"].children.objects
        dev_pod_group = @pod_project["Development Pods"]
        pod_groups += dev_pod_group.children.objects if dev_pod_group
        pod_groups.each do |group|
          resGroup = group["Resources"]
          next unless resGroup
          
          markForRemoval = []
          trimmedBundlesToAdd = Hash.new
          resGroup.files.each do |file|
            keep = true
            if file.path.end_with? ".lproj"
              keep = langs_to_keep.include?(file.path)
            elsif file.path.end_with? ".bundle"
              trimmed_bundle = self.trimmed_bundle(file.real_path)
              if trimmed_bundle 
                trimmedBundlesToAdd[File.basename(file.path)] = trimmed_bundle
                keep = false
              end
            end
            if !keep
              markForRemoval << file
            end
          end
          
          if markForRemoval.length > 0
            Pod::UI.section "Pruning in #{group.path}" do
              markForRemoval.each do |file|
                file.remove_from_project
              end
            end
          end
          
          if trimmedBundlesToAdd.length > 0
            group_path = File.join(@pruned_bundles_path, group.path)
            FileUtils.mkdir group_path unless Dir.exist? group_path
            Pod::UI.message "Adding trimmed bundles to #{group.path}" do
              trimmedBundlesToAdd.each_pair do |bundle_name, bundle_path|
                new_bundle_path = File.join(group_path, bundle_name)
                FileUtils.rm_r(new_bundle_path) if File.exist? new_bundle_path
                FileUtils.mv(bundle_path, new_bundle_path)
                group.new_reference(new_bundle_path)
              end
            end
          end
          
        end
        @pod_project.save
      end
    end
    
    def trimmed_bundle(bundle_path)
      langs_to_keep = @user_options["localizations"] || []
      return unless Dir.exist? bundle_path
      tmp_dir = Dir.mktmpdir
      changed_bundle = false
      Dir.foreach(bundle_path) do |file_name|
        if (file_name == "." || file_name == "..") 
          next
        end
        
        absolute_file_path = File.join(bundle_path, file_name)
        if file_name.end_with? ".lproj"
          if langs_to_keep.include?(file_name)
            FileUtils.cp_r(absolute_file_path, tmp_dir)
          else
            changed_bundle = true
          end
        elsif file_name.end_with? ".bundle"
          sub_trimmed_bundle = self.trimmed_bundle(absolute_file_path)
          if sub_trimmed_bundle
            sub_bundle_path = File.join(tmp_dir, file_name)
            FileUtils.mv(sub_trimmed_bundle, sub_bundle_path)
            changed_bundle = true
          else
            FileUtils.cp_r(absolute_file_path, tmp_dir)
          end
        else
          FileUtils.cp_r(absolute_file_path, tmp_dir)
        end
      end
      
      tmp_dir if changed_bundle
    end
  end
end