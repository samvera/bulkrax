# frozen_string_literal: true

module Bulkrax
  # Shared path-confinement checks used anywhere Bulkrax resolves a
  # caller-supplied relative path against a trusted root directory: ZIP
  # extraction, cloud-file destinations, and filesystem cloud sources.
  #
  # Lexical checks alone (rejecting `..` and absolute paths) don't catch a
  # symlink planted inside the root that points back out of it, so
  # {.confine!} also resolves the longest existing ancestor of the
  # candidate path and checks *that* for escape.
  #
  # @raise [Bulkrax::UnsafePathError] from any public method, never a bare
  #   StandardError, so callers can rescue one error class.
  class SafePath
    # Built via Integer#chr, not a literal escape, so this source
    # file never contains a raw NUL byte (which some tools,
    # including `git diff`, treat as a signal to classify the
    # whole file as binary).
    NUL = 0.chr.freeze

    # Preflight check for a raw, caller-supplied name — a ZIP entry name,
    # or a cloud-file's uploaded filename — before any join, space
    # normalization, or filesystem access. Callers must run this on the
    # *raw* name: joining it under a prefix first (e.g. `File.join('files',
    # name)`) can silently neutralize a leading `/`, which would defeat
    # this check if run afterward. {.confine!} runs it again on the
    # resolved candidate as the final authority.
    #
    # @param name [String] a raw entry/file name
    # @raise [Bulkrax::UnsafePathError] if the name is an absolute path, has
    #   a `..` segment, or contains a NUL byte
    def self.reject_unsafe_entry!(name)
      name = name.to_s
      raise Bulkrax::UnsafePathError, 'path must not contain a NUL byte' if name.include?(NUL)
      raise Bulkrax::UnsafePathError, 'path must not contain a parent-directory reference' if name.split('/').include?('..')
      raise Bulkrax::UnsafePathError, 'path must not be an absolute path' if name.start_with?('/')
    end

    # Resolves `candidate` against `root` and returns the absolute result,
    # but only if it stays inside `root` once both symlinks and `..`
    # segments are resolved.
    #
    # By default `candidate` is held to the same lexical rule as
    # {.reject_unsafe_entry!}: no `..` segment and no leading `/`, even if
    # the fully-resolved result would happen to land inside `root` — a
    # destination filename that only *looks* safe after normalization is
    # still rejected outright, per the plan, rather than silently
    # corrected. The one legitimate exception is a `file:` *source* path
    # (always given as an absolute path by the filesystem provider);
    # pass `allow_absolute: true` for that case. `..` segments are never
    # allowed, even then.
    #
    # @param root [String] trusted directory that the result must stay inside
    # @param candidate [String] a relative (or, with `allow_absolute`, absolute) path to resolve
    # @param require_file [Boolean] when true, reject a result equal to `root` itself
    # @param allow_absolute [Boolean] when true, permit `candidate` to be an absolute path
    # @return [String] absolute path, validated to be inside `root`
    # @raise [Bulkrax::UnsafePathError] if `candidate` is blank, contains a
    #   NUL byte, has a `..` segment, is an absolute path (unless
    #   `allow_absolute`), escapes `root`, or escapes `root` via a symlink
    def self.confine!(root, candidate, require_file: false, allow_absolute: false)
      raise Bulkrax::UnsafePathError, 'path must not be blank' if candidate.blank?

      candidate = candidate.to_s
      if allow_absolute
        raise Bulkrax::UnsafePathError, 'path must not contain a NUL byte' if candidate.include?(NUL)
        raise Bulkrax::UnsafePathError, 'path must not contain a parent-directory reference' if candidate.split('/').include?('..')
      else
        reject_unsafe_entry!(candidate)
      end

      expanded_root = File.expand_path(root)
      expanded_path = File.expand_path(candidate, expanded_root)

      raise Bulkrax::UnsafePathError, 'path escapes the confined root' unless expanded_path == expanded_root || expanded_path.start_with?("#{expanded_root}#{File::SEPARATOR}")
      raise Bulkrax::UnsafePathError, 'a file path is required' if require_file && expanded_path == expanded_root

      reject_symlink_escape!(expanded_root, expanded_path)
      expanded_path
    end

    # True if a filesystem entry exists at `path` — including a dangling
    # symlink. File.exist? follows symlinks and reports `false` for one
    # whose target doesn't exist yet, which is exactly the entry a caller
    # is about to write through, so it can't be the only check here.
    def self.present?(path)
      File.exist?(path) || File.symlink?(path)
    end
    private_class_method :present?

    # Resolves `path` to its real, final location, tolerating a dangling
    # symlink (one whose target doesn't exist) by following the link
    # lexically instead of raising the way File.realpath would. Bounded
    # to 32 hops so a symlink cycle fails closed rather than hanging.
    def self.resolve_fully(path)
      current = path
      32.times do
        return File.realpath(current) if File.exist?(current)
        return current unless File.symlink?(current)
        current = File.expand_path(File.readlink(current), File.dirname(current))
      end
      raise Bulkrax::UnsafePathError, 'path has too many levels of symbolic links'
    end
    private_class_method :resolve_fully

    # Resolves the longest existing-or-dangling-symlink ancestor of
    # `expanded_path` (which may be `expanded_path` itself) and checks it
    # for a symlink escape. Path components that aren't present at all
    # (not even as a symlink) can't be symlinks, so this is the final
    # line of defense without racing the filesystem. As the plan assumes,
    # this is not a guard against a *concurrent* write to the same path —
    # only against a symlink already planted in an application-controlled
    # staging directory.
    def self.reject_symlink_escape!(expanded_root, expanded_path)
      real_root = present?(expanded_root) ? resolve_fully(expanded_root) : expanded_root

      existing_ancestor = expanded_path
      existing_ancestor = File.dirname(existing_ancestor) until present?(existing_ancestor) || existing_ancestor == File.dirname(existing_ancestor)
      return unless present?(existing_ancestor)

      real_existing = resolve_fully(existing_ancestor)

      # existing_ancestor is normally at or below root (inside expanded_path's
      # own subtree) and must resolve to somewhere inside real_root. But when
      # root itself doesn't exist yet (e.g. a first-time extraction
      # destination), the walk climbs past root to a shallower ancestor —
      # the relationship is reversed, and it's real_root that must resolve
      # to somewhere inside (or at) real_existing instead.
      ancestor_within_root = existing_ancestor == expanded_root || existing_ancestor.start_with?("#{expanded_root}#{File::SEPARATOR}")
      contained = if ancestor_within_root
                    real_existing == real_root || real_existing.start_with?("#{real_root}#{File::SEPARATOR}")
                  else
                    real_root == real_existing || real_root.start_with?("#{real_existing}#{File::SEPARATOR}")
                  end
      return if contained

      raise Bulkrax::UnsafePathError, 'path escapes the confined root via a symlink'
    end
    private_class_method :reject_symlink_escape!
  end
end
