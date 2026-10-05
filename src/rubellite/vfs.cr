require "./engine"
require "./value"
require "./macros"

module Rubellite
  # In-memory Virtual Filesystem (VFS) for mounting Ruby scripts, packages, and gems
  # directly into CRuby's require and load pipeline with zero disk I/O.
  module VFS
    @@files = Hash(String, String).new
    @@mutex = Mutex.new
    @@ruby_hooked = false

    # Normalizes a path by replacing backslashes and trimming leading dots or slashes
    def self.normalize_path(path : String) : String
      p = path.gsub('\\', '/').strip
      p = p.lstrip("./").lstrip('/')
      p
    end

    # Automatically installs the VFS hooks in CRuby Kernel#require and Kernel#load
    def self.hook_ruby! : Nil
      Rubellite.ensure_init!
      return if @@ruby_hooked
      @@mutex.synchronize do
        return if @@ruby_hooked

        # Register VFS resolution and reader callbacks
        Rubellite.export("__vfs_resolve") do |args|
          path = args[0].to_s
          Rubellite::VFS.mounted?(path).to_ruby
        end

        Rubellite.export("__vfs_read") do |args|
          path = args[0].to_s
          (Rubellite::VFS.read(path) || "").to_ruby
        end

        # Hook Ruby Kernel
        Rubellite.eval(<<-RUBY)
          module Kernel
            alias_method :__rubellite_orig_require, :require unless method_defined?(:__rubellite_orig_require)
            alias_method :__rubellite_orig_load, :load unless method_defined?(:__rubellite_orig_load)

            def require(feature)
              str_feat = feature.to_s
              if Rubellite.__vfs_resolve(str_feat)
                clean_name = str_feat.sub(/\\.rb$/, '')
                vfs_feature = "<vfs>/\#{clean_name}.rb"
                return false if $LOADED_FEATURES.include?(vfs_feature)

                code = Rubellite.__vfs_read(str_feat)
                $LOADED_FEATURES << vfs_feature
                eval(code, TOPLEVEL_BINDING, vfs_feature, 1)
                true
              else
                __rubellite_orig_require(feature)
              end
            end

            def load(file, priv = false)
              str_file = file.to_s
              if Rubellite.__vfs_resolve(str_file)
                clean_name = str_file.sub(/\\.rb$/, '')
                vfs_feature = "<vfs>/\#{clean_name}.rb"
                code = Rubellite.__vfs_read(str_file)
                eval(code, TOPLEVEL_BINDING, vfs_feature, 1)
                true
              else
                __rubellite_orig_load(file, priv)
              end
            end
          end
        RUBY

        @@ruby_hooked = true
      end
    end

    # Mounts an in-memory Ruby script under the given virtual path
    def self.mount(path : String, code : String) : Nil
      hook_ruby!
      norm = normalize_path(path)
      base = norm.ends_with?(".rb") ? norm[0...-3] : norm
      with_rb = "#{base}.rb"

      @@mutex.synchronize do
        @@files[base] = code
        @@files[with_rb] = code
      end
    end

    # Alias for mount
    def self.mount_file(path : String, code : String) : Nil
      mount(path, code)
    end

    # Mounts a dictionary of files under a directory prefix
    def self.mount_dir(prefix : String, files : Hash(String, String)) : Nil
      p = normalize_path(prefix).rstrip('/')
      files.each do |rel_path, content|
        full = p.empty? ? rel_path : "#{p}/#{rel_path}"
        mount(full, content)
      end
    end

    # Mounts a virtual gem bundle with a standard structure: lib/gem_name.rb and optional sub-files
    def self.mount_gem(name : String, files : Hash(String, String)) : Nil
      files.each do |rel_path, content|
        # Mount with and without lib/ prefix for maximum require compatibility
        mount(rel_path, content)
        if rel_path.starts_with?("lib/")
          mount(rel_path.sub(/^lib\//, ""), content)
        end
      end
    end

    # Checks if a virtual path is mounted
    def self.mounted?(path : String) : Bool
      norm = normalize_path(path)
      base = norm.ends_with?(".rb") ? norm[0...-3] : norm
      with_rb = "#{base}.rb"

      @@mutex.synchronize do
        @@files.has_key?(base) || @@files.has_key?(with_rb)
      end
    end

    # Reads the content of a mounted virtual file
    def self.read(path : String) : String?
      norm = normalize_path(path)
      base = norm.ends_with?(".rb") ? norm[0...-3] : norm
      with_rb = "#{base}.rb"

      @@mutex.synchronize do
        @@files[base]? || @@files[with_rb]?
      end
    end

    # Unmounts a virtual file from the VFS
    def self.unmount(path : String) : Bool
      norm = normalize_path(path)
      base = norm.ends_with?(".rb") ? norm[0...-3] : norm
      with_rb = "#{base}.rb"

      @@mutex.synchronize do
        d1 = @@files.delete(base)
        d2 = @@files.delete(with_rb)
        !d1.nil? || !d2.nil?
      end
    end

    # Returns a list of all currently mounted virtual paths
    def self.files : Array(String)
      @@mutex.synchronize do
        @@files.keys.select(&.ends_with?(".rb")).sort
      end
    end

    # Clears all mounted virtual files and resets loaded features in Ruby
    def self.reset! : Nil
      @@mutex.synchronize do
        @@files.clear
      end
      if @@ruby_hooked && Rubellite.initialized?
        Rubellite.eval(<<-RUBY) rescue nil
          $LOADED_FEATURES.reject! { |f| f.start_with?("<vfs>/") }
        RUBY
      end
    end
  end
end
