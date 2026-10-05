require "option_parser"

module Rubellite
  module Tooling
    class RubyVersionBranch
      def self.run(args : Array(String) = ARGV)
        ruby_version = ""
        push = false
        force = false
        primary_branch = detect_primary_branch
        tag_prefix = "ruby-"

        remaining = [] of String

        parser = OptionParser.new do |opts|
          opts.banner = "Usage: crystal run scripts/ruby_version_branch.cr -- <ruby_version> [options]"
          opts.on("-p", "--push", "Push branch and tag to remote origin") { push = true }
          opts.on("-f", "--force", "Force recreate branch if it already exists") { force = true }
          opts.on("-b BRANCH", "--primary=BRANCH", "Specify primary branch (default: #{primary_branch})") { |b| primary_branch = b }
          opts.on("-t PREFIX", "--tag-prefix=PREFIX", "Tag prefix (default: 'ruby-')") { |t| tag_prefix = t }
          opts.on("-h", "--help", "Show help") do
            puts opts
            exit 0
          end
          opts.unknown_args { |raw| remaining = raw }
        end

        parser.parse(args)
        if remaining.empty?
          STDERR.puts "\e[31mError:\e[0m Missing Ruby version (e.g. 4.0.5, 4.0.1, 3.4.0)"
          STDERR.puts "Usage: crystal run scripts/ruby_version_branch.cr -- <ruby_version> [options]"
          exit 1
        end

        ruby_version = remaining.first.strip
        branch_name = ruby_version
        tag_name = "#{tag_prefix}#{ruby_version}"

        puts "\e[1;35m[Ruby Version Tracking]\e[0m Preparing 1-commit branch '\e[1m#{branch_name}\e[0m' and tag '\e[1m#{tag_name}\e[0m'..."

        # 1. Check working directory status
        status = run_cmd("git", ["status", "--porcelain"])
        unless status.strip.empty?
          STDERR.puts "\e[31mError:\e[0m Working directory has uncommitted changes. Stash or commit before creating release branches."
          exit 1
        end

        # 2. Check out primary branch
        puts "  Ensuring on primary branch '\e[36m#{primary_branch}\e[0m'..."
        exec_cmd("git", ["checkout", primary_branch])

        # 3. Check if branch already exists
        branch_exists = !run_cmd("git", ["branch", "--list", branch_name]).strip.empty?
        if branch_exists
          if force
            puts "  Removing existing branch '\e[33m#{branch_name}\e[0m' (-f specified)..."
            exec_cmd("git", ["branch", "-D", branch_name])
          else
            STDERR.puts "\e[31mError:\e[0m Branch '#{branch_name}' already exists. Use --force to recreate it."
            exit 1
          end
        end

        # 4. Create and checkout the branch
        puts "  Creating branch '\e[32m#{branch_name}\e[0m' off '\e[36m#{primary_branch}\e[0m'..."
        exec_cmd("git", ["checkout", "-b", branch_name, primary_branch])

        # 5. Write ruby-version.yml
        v_parts = ruby_version.split(".")
        abi_version = v_parts.size >= 2 ? "#{v_parts[0]}.#{v_parts[1]}.0" : ruby_version
        manifest = <<-YAML
        version: "#{ruby_version}"
        engine: "ruby"
        abi_version: "#{abi_version}"
        min_crystal: ">= 1.10.0"
        prism: true
        YAML

        File.write("ruby-version.yml", manifest.strip + "\n")
        puts "  Updated \e[36mruby-version.yml\e[0m for Ruby #{ruby_version}"

        # 6. Commit single commit (bypassing pre-commit hook so internal shard version is not bumped)
        exec_cmd("git", ["add", "ruby-version.yml"])
        commit_msg = "chore(ruby): track Ruby #{ruby_version} compatibility"
        exec_cmd("git", ["commit", "--no-verify", "--allow-empty", "-m", commit_msg])
        puts "  Committed: '\e[1m#{commit_msg}\e[0m'"

        # 7. Create annotated tag
        tag_exists = !run_cmd("git", ["tag", "-l", tag_name]).strip.empty?
        if tag_exists
          if force
            puts "  Replacing existing tag '\e[33m#{tag_name}\e[0m'..."
            exec_cmd("git", ["tag", "-d", tag_name])
          else
            STDERR.puts "\e[31mError:\e[0m Tag '#{tag_name}' already exists. Use --force to replace it."
            exec_cmd("git", ["checkout", primary_branch])
            exit 1
          end
        end

        exec_cmd("git", ["tag", "-a", tag_name, "-m", "Ruby #{ruby_version} compatibility release"])
        puts "  Created annotated tag: \e[32m#{tag_name}\e[0m"

        # 8. Push if requested
        if push
          puts "  Pushing branch '\e[32m#{branch_name}\e[0m' and tag '\e[32m#{tag_name}\e[0m' to origin..."
          exec_cmd("git", ["push", "-u", "origin", branch_name])
          exec_cmd("git", ["push", "origin", tag_name])
          puts "\e[32m✓\e[0m Pushed to origin successfully!"
        end

        # 9. Return to primary branch
        puts "  Returning to '\e[36m#{primary_branch}\e[0m'..."
        exec_cmd("git", ["checkout", primary_branch])

        puts "\n\e[1;32m[✓] Successfully created 1-commit Ruby version branch '#{branch_name}' and tag '#{tag_name}'!\e[0m"
      end

      private def self.detect_primary_branch : String
        branches = run_cmd("git", ["branch"]).lines.map(&.gsub("*", "").strip)
        if branches.includes?("main")
          "main"
        elsif branches.includes?("master")
          "master"
        else
          "main"
        end
      end

      private def self.run_cmd(cmd : String, args : Array(String)) : String
        io = IO::Memory.new
        res = Process.run(cmd, args, output: io, error: Process::Redirect::Inherit)
        unless res.success?
          raise "Command failed: #{cmd} #{args.join(" ")}"
        end
        io.to_s
      end

      private def self.exec_cmd(cmd : String, args : Array(String))
        res = Process.run(cmd, args, output: Process::Redirect::Inherit, error: Process::Redirect::Inherit)
        unless res.success?
          raise "Command failed: #{cmd} #{args.join(" ")}"
        end
      end
    end
  end
end

Rubellite::Tooling::RubyVersionBranch.run
