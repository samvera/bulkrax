# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Bulkrax::SafePath do
  describe '.reject_unsafe_entry!' do
    it 'allows a plain relative entry' do
      expect { described_class.reject_unsafe_entry!('files/a.jpg') }.not_to raise_error
    end

    it 'rejects an absolute path' do
      expect { described_class.reject_unsafe_entry!('/etc/passwd') }
        .to raise_error(Bulkrax::UnsafePathError)
    end

    it 'rejects a path with a `..` segment' do
      expect { described_class.reject_unsafe_entry!('../evil.txt') }
        .to raise_error(Bulkrax::UnsafePathError)
    end

    it 'rejects a path containing a NUL byte' do
      expect { described_class.reject_unsafe_entry!("foo#{0.chr}.txt") }
        .to raise_error(Bulkrax::UnsafePathError)
    end
  end

  describe '.confine!' do
    let(:root) { File.realpath(Dir.mktmpdir) }

    after { FileUtils.rm_rf(root) }

    it 'returns the resolved path for a valid nested relative path' do
      expect(described_class.confine!(root, 'a/b/c.txt')).to eq(File.join(root, 'a/b/c.txt'))
    end

    it 'allows the root itself when a file is not required' do
      expect(described_class.confine!(root, '.')).to eq(root)
    end

    it 'rejects the root itself when a file is required' do
      expect { described_class.confine!(root, '.', require_file: true) }
        .to raise_error(Bulkrax::UnsafePathError)
    end

    it 'rejects a `..` escape' do
      expect { described_class.confine!(root, '../evil.txt') }
        .to raise_error(Bulkrax::UnsafePathError)
    end

    it 'rejects a sibling-prefix trick (root name is a prefix of a sibling directory)' do
      sibling = "#{root}-evil"
      FileUtils.mkdir_p(sibling)
      begin
        relative = Pathname.new(sibling).relative_path_from(Pathname.new(root)).to_s
        expect { described_class.confine!(root, relative) }
          .to raise_error(Bulkrax::UnsafePathError)
      ensure
        FileUtils.rm_rf(sibling)
      end
    end

    # Destination paths (a cloud-file's uploaded filename, a ZIP entry
    # name) must never be absolute and must never contain `..`, even when
    # the fully-resolved result would happen to land inside root — the
    # plan calls for rejecting a suspicious filename outright rather than
    # silently normalizing the traversal away. `file:` *source* paths are
    # the one legitimate exception (a real local file is always given as
    # an absolute path); those opt in with `allow_absolute: true`.
    it 'rejects an absolute candidate by default, even when it resolves inside root' do
      inside = File.join(root, 'nested.txt')
      expect { described_class.confine!(root, inside) }
        .to raise_error(Bulkrax::UnsafePathError)
    end

    it 'rejects a `..` segment by default, even when it resolves inside root' do
      expect { described_class.confine!(root, 'a/../nested.txt') }
        .to raise_error(Bulkrax::UnsafePathError)
    end

    it 'accepts an absolute candidate that resolves inside root when allow_absolute: true' do
      inside = File.join(root, 'nested.txt')
      expect(described_class.confine!(root, inside, allow_absolute: true)).to eq(inside)
    end

    it 'rejects an absolute candidate that resolves outside root even when allow_absolute: true' do
      outside = File.realpath(Dir.mktmpdir)
      begin
        expect { described_class.confine!(root, outside, allow_absolute: true) }
          .to raise_error(Bulkrax::UnsafePathError)
      ensure
        FileUtils.rm_rf(outside)
      end
    end

    it 'still rejects a `..` segment when allow_absolute: true' do
      expect { described_class.confine!(root, 'a/../../etc/passwd', allow_absolute: true) }
        .to raise_error(Bulkrax::UnsafePathError)
    end

    it 'rejects a blank path' do
      expect { described_class.confine!(root, '') }.to raise_error(Bulkrax::UnsafePathError)
    end

    it 'rejects a NUL byte in the candidate' do
      expect { described_class.confine!(root, "a#{0.chr}b") }.to raise_error(Bulkrax::UnsafePathError)
    end

    it 'rejects a NUL byte in the candidate even when allow_absolute: true' do
      expect { described_class.confine!(root, "a#{0.chr}b", allow_absolute: true) }
        .to raise_error(Bulkrax::UnsafePathError)
    end

    context 'when an existing ancestor is a symlink that escapes root' do
      it 'rejects the escape even though the lexical path looks contained' do
        outside = File.realpath(Dir.mktmpdir)
        begin
          FileUtils.mkdir_p(File.join(root, 'linked'))
          FileUtils.rm_rf(File.join(root, 'linked'))
          File.symlink(outside, File.join(root, 'linked'))

          expect { described_class.confine!(root, 'linked/evil.txt') }
            .to raise_error(Bulkrax::UnsafePathError)
        ensure
          FileUtils.rm_rf(outside)
        end
      end
    end

    context 'when the target itself already exists as a symlink escaping root' do
      it 'rejects the escape' do
        outside = File.realpath(Dir.mktmpdir)
        begin
          outside_file = File.join(outside, 'secret.txt')
          File.write(outside_file, 'secret')
          File.symlink(outside_file, File.join(root, 'planted.txt'))

          expect { described_class.confine!(root, 'planted.txt') }
            .to raise_error(Bulkrax::UnsafePathError)
        ensure
          FileUtils.rm_rf(outside)
        end
      end
    end

    context 'when a nested directory does not exist yet' do
      it 'still allows the valid nested path (no false positive)' do
        expect(described_class.confine!(root, 'brand/new/dir/file.txt', require_file: true))
          .to eq(File.join(root, 'brand/new/dir/file.txt'))
      end
    end

    # root itself may not exist yet (e.g. a first-time ZIP extraction
    # destination): the walk up from the candidate then climbs past root
    # to a shallower, pre-existing ancestor. That direction must not be
    # mistaken for an escape -- only a genuine symlink planted along the
    # way should be.
    context 'when root itself does not exist yet' do
      it 'still allows a valid nested path under the not-yet-created root (no false positive)' do
        nonexistent_root = File.join(root, 'not-yet-created')

        expect(described_class.confine!(nonexistent_root, 'nested/file.txt'))
          .to eq(File.join(nonexistent_root, 'nested/file.txt'))
      end

      it 'still rejects an escape via a symlink planted above the not-yet-created root' do
        outside = File.realpath(Dir.mktmpdir)
        begin
          FileUtils.mkdir_p(File.join(root, 'linked'))
          FileUtils.rm_rf(File.join(root, 'linked'))
          File.symlink(outside, File.join(root, 'linked'))
          nonexistent_root = File.join(root, 'linked', 'not-yet-created')

          expect { described_class.confine!(nonexistent_root, 'nested/file.txt') }
            .to raise_error(Bulkrax::UnsafePathError)
        ensure
          FileUtils.rm_rf(outside)
        end
      end
    end

    # File.exist? follows symlinks, so it reports `false` for a dangling
    # symlink (one whose target doesn't exist yet) — exactly the entry a
    # caller is about to write through. A check built on File.exist? alone
    # would skip right over it and let the write land wherever the link
    # points, outside root.
    context 'when the target is a dangling symlink pointing outside root' do
      it 'rejects the escape without ever creating or truncating the external target' do
        outside_dir = File.realpath(Dir.mktmpdir)
        outside_target = File.join(outside_dir, 'does-not-exist-yet.txt')
        begin
          File.symlink(outside_target, File.join(root, 'planted.txt'))

          expect { described_class.confine!(root, 'planted.txt', require_file: true) }
            .to raise_error(Bulkrax::UnsafePathError)

          expect(File).not_to exist(outside_target)
        ensure
          FileUtils.rm_rf(outside_dir)
        end
      end
    end

    context 'when an existing ancestor is a dangling symlink pointing outside root' do
      it 'rejects the escape' do
        outside_dir = File.realpath(Dir.mktmpdir)
        outside_target = File.join(outside_dir, 'does-not-exist-yet')
        begin
          File.symlink(outside_target, File.join(root, 'linked'))

          expect { described_class.confine!(root, 'linked/evil.txt', require_file: true) }
            .to raise_error(Bulkrax::UnsafePathError)

          expect(File).not_to exist(outside_target)
        ensure
          FileUtils.rm_rf(outside_dir)
        end
      end
    end
  end
end
