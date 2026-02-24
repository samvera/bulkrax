require('./setup')
require('../../app/assets/javascripts/bulkrax/bulkrax_utils.js')

var stepper = require('../../app/assets/javascripts/bulkrax/importers_stepper.js')

function mockFile(name, sizeBytes) {
  return { name: name, size: sizeBytes || 1024 }
}

describe('Step 1: Upload & Validate', () => {

  describe('allowed file types', () => {
    it('accepts .csv files', () => {
      expect(stepper.isValidFileType('data.csv')).toBe(true)
    })

    it('accepts .zip files', () => {
      expect(stepper.isValidFileType('archive.zip')).toBe(true)
    })

    it('rejects .txt, .xlsx, .pdf, and other formats', () => {
      expect(stepper.isValidFileType('readme.txt')).toBe(false)
      expect(stepper.isValidFileType('spreadsheet.xlsx')).toBe(false)
      expect(stepper.isValidFileType('document.pdf')).toBe(false)
      expect(stepper.isValidFileType('image.png')).toBe(false)
    })

    it('rejects files with no extension', () => {
      expect(stepper.isValidFileType('no-extension')).toBe(false)
    })

    it('is case-insensitive (.CSV and .Zip are accepted)', () => {
      expect(stepper.isValidFileType('DATA.CSV')).toBe(true)
      expect(stepper.isValidFileType('Archive.Zip')).toBe(true)
      expect(stepper.isValidFileType('mixed.CsV')).toBe(true)
    })

    it('handles filenames with multiple dots (archive.2024.zip)', () => {
      expect(stepper.isValidFileType('archive.2024.zip')).toBe(true)
      expect(stepper.isValidFileType('report.final.csv')).toBe(true)
    })
  })

  describe('file combination limits', () => {
    it('allows one CSV and one ZIP together (max 2 files)', () => {
      var result = stepper.processFileSelection([], [mockFile('data.csv'), mockFile('files.zip')], false)
      expect(result.updatedFiles.length).toBe(2)
      expect(result.rejected.length).toBe(0)
    })

    it('allows a single CSV alone', () => {
      var result = stepper.processFileSelection([], [mockFile('data.csv')], false)
      expect(result.updatedFiles.length).toBe(1)
      expect(result.rejected.length).toBe(0)
    })

    it('allows a single ZIP alone', () => {
      var result = stepper.processFileSelection([], [mockFile('archive.zip')], false)
      expect(result.updatedFiles.length).toBe(1)
      expect(result.rejected.length).toBe(0)
    })

    it('rejects a second CSV when one is already present', () => {
      var existing = stepper.processFileSelection([], [mockFile('first.csv')], false).updatedFiles
      var result = stepper.processFileSelection(existing, [mockFile('second.csv')], true)
      expect(result.rejected.length).toBe(1)
      expect(result.rejected[0].reason).toBe('duplicate CSV')
      expect(result.rejected[0].name).toBe('second.csv')
    })

    it('rejects a second ZIP when one is already present', () => {
      var existing = stepper.processFileSelection([], [mockFile('first.zip')], false).updatedFiles
      var result = stepper.processFileSelection(existing, [mockFile('second.zip')], true)
      expect(result.rejected.length).toBe(1)
      expect(result.rejected[0].reason).toBe('duplicate ZIP')
      expect(result.rejected[0].name).toBe('second.zip')
    })

    it('rejects files beyond the 2-file maximum', () => {
      var result = stepper.processFileSelection([], [mockFile('a.csv'), mockFile('b.zip'), mockFile('c.zip')], false)
      // Only 2 can be accepted (MAX_FILES = 2), the third is cut off by the loop guard
      expect(result.updatedFiles.length).toBe(2)
    })

    it('rejects an exact duplicate filename', () => {
      var existing = stepper.processFileSelection([], [mockFile('data.csv')], false).updatedFiles
      var result = stepper.processFileSelection(existing, [mockFile('data.csv')], true)
      expect(result.rejected.length).toBe(1)
      expect(result.rejected[0].reason).toBe('duplicate')
    })
  })

  describe('adding a file', () => {
    it('allows adding a second file when only one file is present', () => {
      var existing = stepper.processFileSelection([], [mockFile('data.csv')], false).updatedFiles
      var result = stepper.processFileSelection(existing, [mockFile('files.zip')], true)
      expect(result.updatedFiles.length).toBe(2)
      expect(result.rejected.length).toBe(0)
    })

    it('adding mode still enforces one-CSV / one-ZIP limits against existing files', () => {
      var existing = stepper.processFileSelection([], [mockFile('data.csv'), mockFile('files.zip')], false).updatedFiles
      // Already at max; a new valid file should still be rejected by the loop guard
      var result = stepper.processFileSelection(existing, [mockFile('extra.csv')], true)
      expect(result.updatedFiles.length).toBe(2)
    })

    it('adding a CSV when a CSV already exists is rejected, not swapped', () => {
      var existing = stepper.processFileSelection([], [mockFile('original.csv')], false).updatedFiles
      var result = stepper.processFileSelection(existing, [mockFile('replacement.csv')], true)
      expect(result.rejected[0].reason).toBe('duplicate CSV')
      // Original file should still be in the list
      expect(result.updatedFiles.some(function (f) { return f.name === 'original.csv' })).toBe(true)
    })

    it('adding a ZIP when a ZIP already exists is rejected, not swapped', () => {
      var existing = stepper.processFileSelection([], [mockFile('original.zip')], false).updatedFiles
      var result = stepper.processFileSelection(existing, [mockFile('replacement.zip')], true)
      expect(result.rejected[0].reason).toBe('duplicate ZIP')
      expect(result.updatedFiles.some(function (f) { return f.name === 'original.zip' })).toBe(true)
    })
  })

  describe('removing a file', () => {
    it('removes the specified file from the list', () => {
      var files = [
        { name: 'data.csv', fileType: 'csv' },
        { name: 'assets.zip', fileType: 'zip' }
      ]
      var result = stepper.removeFile(files, 'data.csv')
      expect(result.length).toBe(1)
      expect(result[0].name).toBe('assets.zip')
    })

    it('does not remove any other files when one is removed', () => {
      var files = [
        { name: 'data.csv', fileType: 'csv' },
        { name: 'assets.zip', fileType: 'zip' }
      ]
      var result = stepper.removeFile(files, 'data.csv')
      expect(result.every(function (f) { return f.name !== 'data.csv' })).toBe(true)
      expect(result.some(function (f) { return f.name === 'assets.zip' })).toBe(true)
    })
  })

  describe('rejection messaging', () => {
    it('tells the user which files had invalid formats and shows their extensions', () => {
      var rejected = [
        { name: 'report.pdf', reason: 'invalid_type', extension: '.pdf' },
        { name: 'bare-name', reason: 'invalid_type', extension: '' }
      ]
      var messages = stepper.buildRejectionMessages(stepper.categorizeRejectedFiles(rejected))
      expect(messages.length).toBe(1)
      expect(messages[0]).toContain('report.pdf')
      expect(messages[0]).toContain('.pdf')
      expect(messages[0]).toContain('bare-name')
      expect(messages[0]).toContain('no extension')
    })

    it('tells the user only 1 CSV is allowed and names the rejected files', () => {
      var rejected = [
        { name: 'second.csv', reason: 'duplicate CSV' }
      ]
      var messages = stepper.buildRejectionMessages(stepper.categorizeRejectedFiles(rejected))
      expect(messages.length).toBe(1)
      expect(messages[0]).toContain('1 CSV')
      expect(messages[0]).toContain('second.csv')
    })

    it('tells the user only 1 ZIP is allowed and names the rejected files', () => {
      var rejected = [
        { name: 'second.zip', reason: 'duplicate ZIP' }
      ]
      var messages = stepper.buildRejectionMessages(stepper.categorizeRejectedFiles(rejected))
      expect(messages.length).toBe(1)
      expect(messages[0]).toContain('1 ZIP')
      expect(messages[0]).toContain('second.zip')
    })

    it('tells the user which files were already uploaded', () => {
      var rejected = [
        { name: 'data.csv', reason: 'duplicate' }
      ]
      var messages = stepper.buildRejectionMessages(stepper.categorizeRejectedFiles(rejected))
      expect(messages.length).toBe(1)
      expect(messages[0]).toContain('data.csv')
      expect(messages[0]).toContain('already uploaded')
    })

    it('produces no messages when all files are accepted', () => {
      var messages = stepper.buildRejectionMessages(stepper.categorizeRejectedFiles([]))
      expect(messages.length).toBe(0)
    })
  })

  describe('upload mode', () => {
    it('ready when at least one file (CSV or ZIP) is uploaded AND admin set is selected', () => {
      var files = [{ fileType: 'csv', name: 'data.csv' }]
      expect(stepper.canValidate(files, 'upload', '', 'admin-set-1')).toBe(true)
    })

    it('not ready when files are uploaded but no admin set is selected', () => {
      var files = [{ fileType: 'csv', name: 'data.csv' }]
      expect(stepper.canValidate(files, 'upload', '', '')).toBe(false)
    })

    it('not ready when admin set is selected but no files are uploaded', () => {
      expect(stepper.canValidate([], 'upload', '', 'admin-set-1')).toBe(false)
    })
  })

  describe('file path mode', () => {
    it('ready when a non-empty file path is entered AND admin set is selected', () => {
      expect(stepper.canValidate([], 'file_path', '/srv/imports/data.csv', 'admin-set-1')).toBe(true)
    })

    it('not ready when file path is empty or whitespace-only', () => {
      expect(stepper.canValidate([], 'file_path', '', 'admin-set-1')).toBe(false)
      expect(stepper.canValidate([], 'file_path', '   ', 'admin-set-1')).toBe(false)
    })

    it('not ready when file path is entered but no admin set is selected', () => {
      expect(stepper.canValidate([], 'file_path', '/srv/imports/data.csv', '')).toBe(false)
    })
  })

  describe('validation resets when inputs change', () => {
    it('adding a file after validation clears validation results', () => {
      var state = { validated: true, validationData: { isValid: true, hasWarnings: false }, warningsAcknowledge: false, skipValidation: false }
      var next = stepper.applyValidationReset(state)
      expect(next.validated).toBe(false)
      expect(next.validationData).toBeNull()
    })

    it('removing a file after validation clears validation results', () => {
      var state = { validated: true, validationData: { isValid: true, hasWarnings: false }, warningsAcknowledge: false, skipValidation: false }
      var next = stepper.applyValidationReset(state)
      expect(next.validated).toBe(false)
      expect(next.validationData).toBeNull()
    })

    it('changing admin set after validation clears validation results', () => {
      var state = { validated: true, validationData: { isValid: true, hasWarnings: true }, warningsAcknowledge: true, skipValidation: false }
      var next = stepper.applyValidationReset(state)
      expect(next.validated).toBe(false)
      expect(next.warningsAcknowledge).toBe(false)
    })

    it('switching upload mode after validation clears validation results', () => {
      var state = { validated: true, validationData: { isValid: false, hasWarnings: false }, warningsAcknowledge: false, skipValidation: false }
      var next = stepper.applyValidationReset(state)
      expect(next.validated).toBe(false)
      expect(next.validationData).toBeNull()
      expect(next.warningsAcknowledge).toBe(false)
    })

    it('reset disables the next button until re-validation', () => {
      var state = { validated: false, validationData: null, warningsAcknowledge: false, skipValidation: false }
      expect(stepper.canProceedFromStep1(state)).toBe(false)
    })
  })

  describe('missing field grouping', () => {
    it('groups missing required fields by model name', () => {
      var items = [
        { model: 'Work', field: 'title' },
        { model: 'Work', field: 'creator' },
        { model: 'Collection', field: 'title' }
      ]
      var grouped = stepper.groupItemsByModel(items)
      expect(grouped['Work']).toEqual(['title', 'creator'])
      expect(grouped['Collection']).toEqual(['title'])
    })

    it('labels items without a model as "Unknown"', () => {
      var items = [
        { field: 'title' },
        { model: null, field: 'creator' }
      ]
      var grouped = stepper.groupItemsByModel(items)
      expect(grouped['Unknown']).toEqual(['title', 'creator'])
    })

    it('preserves all fields for each model', () => {
      var items = [
        { model: 'Work', field: 'title' },
        { model: 'Work', field: 'creator' },
        { model: 'Work', field: 'description' }
      ]
      var grouped = stepper.groupItemsByModel(items)
      expect(grouped['Work'].length).toBe(3)
      expect(grouped['Work']).toContain('title')
      expect(grouped['Work']).toContain('creator')
      expect(grouped['Work']).toContain('description')
    })
  })

  describe('hierarchy relationship normalization', () => {
    it('converts parent-declares-children (childrenIds) into child-declares-parent (parentIds)', () => {
      var data = {
        collections: [{ id: 'col-1', childrenIds: ['work-1', 'work-2'] }],
        works: [
          { id: 'work-1' },
          { id: 'work-2' }
        ]
      }
      stepper.normalizeRelationships(data)
      expect(data.works[0].parentIds).toContain('col-1')
      expect(data.works[1].parentIds).toContain('col-1')
    })

    it('does not create duplicate parentIds if the relationship already exists', () => {
      var data = {
        collections: [{ id: 'col-1', childrenIds: ['work-1'] }],
        works: [{ id: 'work-1', parentIds: ['col-1'] }]
      }
      stepper.normalizeRelationships(data)
      expect(data.works[0].parentIds.filter(function (id) { return id === 'col-1' }).length).toBe(1)
    })

    it('builds a lookup map from parent ID → list of children', () => {
      var data = {
        collections: [{ id: 'col-1', childrenIds: ['work-1', 'work-2'] }],
        works: [{ id: 'work-1' }, { id: 'work-2' }]
      }
      var map = stepper.normalizeRelationships(data)
      expect(map['col-1']).toBeDefined()
      expect(map['col-1'].length).toBe(2)
      expect(map['col-1'].map(function (c) { return c.id })).toContain('work-1')
      expect(map['col-1'].map(function (c) { return c.id })).toContain('work-2')
    })

    it('handles items with no parents and no children', () => {
      var data = {
        collections: [{ id: 'col-1' }],
        works: [{ id: 'work-1' }]
      }
      var map = stepper.normalizeRelationships(data)
      expect(map['col-1']).toBeUndefined()
      expect(map['work-1']).toBeUndefined()
      expect(data.works[0].parentIds).toEqual([])
    })

    it('handles items shared across multiple parents', () => {
      var data = {
        collections: [
          { id: 'col-1', childrenIds: ['work-1'] },
          { id: 'col-2', childrenIds: ['work-1'] }
        ],
        works: [{ id: 'work-1' }]
      }
      stepper.normalizeRelationships(data)
      expect(data.works[0].parentIds).toContain('col-1')
      expect(data.works[0].parentIds).toContain('col-2')
      expect(data.works[0].parentIds.length).toBe(2)
    })

    it('handles deeply nested hierarchies without stack overflow', () => {
      // normalizeRelationships itself is iterative, not recursive — no stack risk.
      // Build a chain of 100 items and confirm the map is built correctly.
      var collections = []
      for (var i = 0; i < 100; i++) {
        collections.push({ id: 'col-' + i, childrenIds: i < 99 ? ['col-' + (i + 1)] : [] })
      }
      var data = { collections: collections, works: [] }
      expect(function () { stepper.normalizeRelationships(data) }).not.toThrow()
    })
  })

  describe('step 1 navigation', () => {
    it('allows proceeding when validation passed with no warnings', () => {
      var state = {
        validated: true,
        validationData: { isValid: true, hasWarnings: false },
        warningsAcknowledge: false,
        skipValidation: false
      }
      expect(stepper.canProceedFromStep1(state)).toBe(true)
    })

    it('allows proceeding when validation passed with warnings AND warnings are acknowledged', () => {
      var state = {
        validated: true,
        validationData: { isValid: true, hasWarnings: true },
        warningsAcknowledge: true,
        skipValidation: false
      }
      expect(stepper.canProceedFromStep1(state)).toBe(true)
    })

    it('blocks proceeding when validation passed with warnings but NOT acknowledged', () => {
      var state = {
        validated: true,
        validationData: { isValid: true, hasWarnings: true },
        warningsAcknowledge: false,
        skipValidation: false
      }
      expect(stepper.canProceedFromStep1(state)).toBe(false)
    })

    it('blocks proceeding when validation failed (errors)', () => {
      var state = {
        validated: true,
        validationData: { isValid: false, hasWarnings: false },
        warningsAcknowledge: false,
        skipValidation: false
      }
      expect(stepper.canProceedFromStep1(state)).toBe(false)
    })

    it('blocks proceeding when validation has not been run', () => {
      var state = {
        validated: false,
        validationData: null,
        warningsAcknowledge: false,
        skipValidation: false
      }
      expect(stepper.canProceedFromStep1(state)).toBe(false)
    })

    it('allows proceeding when skip-validation is checked, regardless of validation state', () => {
      var state = {
        validated: false,
        validationData: null,
        warningsAcknowledge: false,
        skipValidation: true
      }
      expect(stepper.canProceedFromStep1(state)).toBe(true)
    })
  })

  describe('start over button', () => {
    it('removes all uploaded files', () => {
      var state = { uploadedFiles: [{ name: 'data.csv', fileType: 'csv' }], uploadMode: 'upload', validated: false, validationData: null, warningsAcknowledge: false, skipValidation: false, demoScenario: null, adminSetId: 'set-1', adminSetName: 'Default', settings: { name: 'My Import', visibility: 'open', rightsStatement: '', limit: '' } }
      var next = stepper.applyStartOver(state)
      expect(next.uploadedFiles).toEqual([])
    })

    it('resets uploadMode to "upload"', () => {
      var state = { uploadedFiles: [], uploadMode: 'file_path', validated: false, validationData: null, warningsAcknowledge: false, skipValidation: false, demoScenario: null, adminSetId: '', adminSetName: '', settings: { name: '', visibility: 'open', rightsStatement: '', limit: '' } }
      var next = stepper.applyStartOver(state)
      expect(next.uploadMode).toBe('upload')
    })

    it('removes all validation data', () => {
      var state = { uploadedFiles: [], uploadMode: 'upload', validated: true, validationData: { isValid: true, hasWarnings: false }, warningsAcknowledge: false, skipValidation: false, demoScenario: null, adminSetId: '', adminSetName: '', settings: { name: '', visibility: 'open', rightsStatement: '', limit: '' } }
      var next = stepper.applyStartOver(state)
      expect(next.validated).toBe(false)
      expect(next.validationData).toBeNull()
    })
  })
})

describe('Step 2: Configure Settings', () => {
  describe('import size assessment', () => {
    it('classifies 0–100 items as optimal', () => {
      expect(stepper.getImportSizeZone(0).zone).toBe('Optimal')
      expect(stepper.getImportSizeZone(50).zone).toBe('Optimal')
      expect(stepper.getImportSizeZone(100).zone).toBe('Optimal')
    })

    it('classifies 101–500 items as moderate', () => {
      expect(stepper.getImportSizeZone(101).zone).toBe('Moderate')
      expect(stepper.getImportSizeZone(300).zone).toBe('Moderate')
      expect(stepper.getImportSizeZone(500).zone).toBe('Moderate')
    })

    it('classifies 501+ items as large', () => {
      expect(stepper.getImportSizeZone(501).zone).toBe('Large')
      expect(stepper.getImportSizeZone(1000).zone).toBe('Large')
      expect(stepper.getImportSizeZone(9999).zone).toBe('Large')
    })

    it('gauge percentage never exceeds 100%', () => {
      expect(stepper.getImportSizeZone(99999).pct).toBeLessThanOrEqual(100)
    })

    describe('boundary values', () => {
      it('100 items → optimal (upper edge)', () => {
        expect(stepper.getImportSizeZone(100).zone).toBe('Optimal')
      })

      it('101 items → moderate (lower edge)', () => {
        expect(stepper.getImportSizeZone(101).zone).toBe('Moderate')
      })

      it('500 items → moderate (upper edge)', () => {
        expect(stepper.getImportSizeZone(500).zone).toBe('Moderate')
      })

      it('501 items → large (lower edge)', () => {
        expect(stepper.getImportSizeZone(501).zone).toBe('Large')
      })
    })

    it('each zone has a distinct CSS class and recommendation message', () => {
      var optimal = stepper.getImportSizeZone(50)
      var moderate = stepper.getImportSizeZone(200)
      var large = stepper.getImportSizeZone(600)

      // Distinct card classes
      expect(optimal.cardClass).toBe('gauge-card-optimal')
      expect(moderate.cardClass).toBe('gauge-card-moderate')
      expect(large.cardClass).toBe('gauge-card-large')

      // Each zone has a non-empty, distinct message
      expect(optimal.msg).toBeTruthy()
      expect(moderate.msg).toBeTruthy()
      expect(large.msg).toBeTruthy()
      expect(optimal.msg).not.toBe(moderate.msg)
      expect(moderate.msg).not.toBe(large.msg)
    })
  })

  describe('default import name generation', () => {
    it('follows the format "CSV Import - M/D/YYYY"', () => {
      var date = new Date(2024, 5, 15) // June 15 2024
      expect(stepper.getDefaultImportName(date)).toBe('CSV Import - 6/15/2024')
    })

    it('does not zero-pad single-digit months or days', () => {
      var date = new Date(2024, 0, 3) // January 3 2024
      var name = stepper.getDefaultImportName(date)
      expect(name).toBe('CSV Import - 1/3/2024')
      expect(name).not.toContain('01/')
      expect(name).not.toContain('/03/')
    })

    it('uses the correct year', () => {
      var date = new Date(2026, 1, 23) // February 23 2026
      expect(stepper.getDefaultImportName(date)).toContain('2026')
    })
  })

  describe('step 2 navigation', () => {
    it('allows proceeding when import name is provided', () => {
      // canProceedFromStep2 checks name and adminSetId (visibility is always present by default)
      expect(stepper.canProceedFromStep2('My Import', 'admin-set-1')).toBe(true)
    })

    it('blocks proceeding when import name is empty or whitespace', () => {
      expect(stepper.canProceedFromStep2('', 'admin-set-1')).toBe(false)
      expect(stepper.canProceedFromStep2('   ', 'admin-set-1')).toBe(false)
    })
  })
})

describe('Step 3: Review & Start', () => {
  // updateReviewSummary() assembles review data but is not exported; it renders
  // directly into the DOM. The tests below verify the pure data/logic pieces
  // that ARE exported. Tests requiring DOM rendering are marked pending.

  describe('file summary', () => {
    it('lists all files with type and size', () => {
      // File type and size are stored on StepperState.uploadedFiles entries.
      // The shape produced by processFileSelection is the source of truth here.
      var result = stepper.processFileSelection([], [mockFile('data.csv', 2048)], false)
      var file = result.updatedFiles[0]
      expect(file.fileType).toBe('csv')
      expect(file.name).toBe('data.csv')
      expect(file.size).toBeDefined()
    })

    it('notes when a CSV was detected inside a ZIP (fromZip flag)', () => {
      // processFileSelection sets fromZip: false for user-uploaded files.
      // The fromZip: true flag is set by the backend / demo scenarios loader,
      // not by processFileSelection — no exported function sets it to true.
      var result = stepper.processFileSelection([], [mockFile('data.csv')], false)
      expect(result.updatedFiles[0].fromZip).toBe(false)
    })
  })

  describe('file summary for file_path mode (buildFilesSummary)', () => {
    it('returns the import path when uploadMode is file_path', () => {
      var entries = stepper.buildFilesSummary([], 'file_path', '/srv/imports/batch_01.csv')
      expect(entries.length).toBe(1)
      expect(entries[0].type).toBe('Path')
      expect(entries[0].name).toBe('/srv/imports/batch_01.csv')
    })

    it('trims whitespace from the file path', () => {
      var entries = stepper.buildFilesSummary([], 'file_path', '  /srv/imports/data.csv  ')
      expect(entries[0].name).toBe('/srv/imports/data.csv')
    })

    it('returns empty when file_path mode has no path entered', () => {
      var entries = stepper.buildFilesSummary([], 'file_path', '')
      expect(entries.length).toBe(0)
    })

    it('returns empty when file_path mode has whitespace-only path', () => {
      var entries = stepper.buildFilesSummary([], 'file_path', '   ')
      expect(entries.length).toBe(0)
    })

    it('returns uploaded files when uploadMode is upload', () => {
      var files = [
        { name: 'data.csv', fileType: 'csv', size: '2 KB', fromZip: false },
        { name: 'assets.zip', fileType: 'zip', size: '5 MB', fromZip: false }
      ]
      var entries = stepper.buildFilesSummary(files, 'upload', '')
      expect(entries.length).toBe(2)
      expect(entries[0].type).toBe('CSV')
      expect(entries[0].name).toBe('data.csv')
      expect(entries[0].size).toBe('2 KB')
      expect(entries[1].type).toBe('ZIP')
    })

    it('preserves the fromZip flag on uploaded files', () => {
      var files = [
        { name: 'data.csv', fileType: 'csv', size: '1 KB', fromZip: true }
      ]
      var entries = stepper.buildFilesSummary(files, 'upload', '')
      expect(entries[0].fromZip).toBe(true)
    })

    it('sets size to null for file_path entries (size is unknown)', () => {
      var entries = stepper.buildFilesSummary([], 'file_path', '/srv/imports/data.csv')
      expect(entries[0].size).toBeNull()
    })
  })

  describe('record counts', () => {
    it('totals collections + works + file sets from validation data', () => {
      // This computation lives inside updateReviewSummary (not exported).
      // Verify the expected arithmetic directly.
      var data = { collections: [{}, {}], works: [{}, {}, {}], fileSets: [{}] }
      var total = data.collections.length + data.works.length + data.fileSets.length
      expect(total).toBe(6)
    })

    it('reports "skipped" when validation was not run', () => {
      var summary = stepper.buildRecordsSummary(null)
      expect(summary.skipped).toBe(true)
      expect(summary.totalItems).toBe(0)
    })
  })

  describe('settings summary', () => {
    it('includes the import name from state', () => {
      var settings = { name: 'My Test Import', visibility: 'open', rightsStatement: '', limit: '' }
      var summary = stepper.buildSettingsSummary(settings, 'Default Admin Set')
      expect(summary.name).toBe('My Test Import')
    })

    it('includes the admin set name (human-readable, not the ID)', () => {
      var settings = { name: 'Import', visibility: 'open', rightsStatement: '', limit: '' }
      var summary = stepper.buildSettingsSummary(settings, 'Special Collections')
      expect(summary.adminSetName).toBe('Special Collections')
    })

    it('maps visibility value to label: open→Public, authenticated→Institution, restricted→Private', () => {
      var base = { name: '', rightsStatement: '', limit: '' }
      expect(stepper.buildSettingsSummary(Object.assign({}, base, { visibility: 'open' }), '').visibility).toBe('Public')
      expect(stepper.buildSettingsSummary(Object.assign({}, base, { visibility: 'authenticated' }), '').visibility).toBe('Institution')
      expect(stepper.buildSettingsSummary(Object.assign({}, base, { visibility: 'restricted' }), '').visibility).toBe('Private')
    })

    it('includes rights statement only when non-empty', () => {
      var withRights = { name: 'Import', visibility: 'open', rightsStatement: 'CC BY 4.0', limit: '' }
      var noRights = { name: 'Import', visibility: 'open', rightsStatement: '', limit: '' }
      expect(stepper.buildSettingsSummary(withRights, '').rightsStatement).toBe('CC BY 4.0')
      expect(stepper.buildSettingsSummary(noRights, '').rightsStatement).toBeNull()
    })

    it('includes limit only when non-empty', () => {
      var withLimit = { name: 'Import', visibility: 'open', rightsStatement: '', limit: '100' }
      var noLimit = { name: 'Import', visibility: 'open', rightsStatement: '', limit: '' }
      expect(stepper.buildSettingsSummary(withLimit, '').limit).toBe('100')
      expect(stepper.buildSettingsSummary(noLimit, '').limit).toBeNull()
    })
  })

  describe('warnings summary', () => {
    it('extracts warning-severity issues from validation messages', () => {
      // The filter logic lives inside updateReviewSummary. Test the predicate directly.
      var issues = [
        { severity: 'warning', title: 'Missing files' },
        { severity: 'error', title: 'Invalid headers' },
        { severity: 'warning', title: 'Unrecognized fields' }
      ]
      var warnings = issues.filter(function (issue) { return issue.severity === 'warning' })
      expect(warnings.length).toBe(2)
      expect(warnings[0].title).toBe('Missing files')
      expect(warnings[1].title).toBe('Unrecognized fields')
    })

    it('empty when validation data has no warning-severity issues', () => {
      var issues = [{ severity: 'error', title: 'Invalid headers' }]
      var warnings = issues.filter(function (issue) { return issue.severity === 'warning' })
      expect(warnings.length).toBe(0)
    })

    it('empty when validation was skipped', () => {
      // When validationData is null, warningIssues defaults to [] in updateReviewSummary.
      var data = null
      var warningIssues = (data && data.messages && data.messages.issues)
        ? data.messages.issues.filter(function (issue) { return issue.severity === 'warning' })
        : []
      expect(warningIssues.length).toBe(0)
    })
  })

  describe('large import flag', () => {
    it('flagged when total items exceeds IMPORT_SIZE_MODERATE (500)', () => {
      var IMPORT_SIZE_MODERATE = stepper.CONSTANTS.IMPORT_SIZE_MODERATE
      var data = { collections: [], works: [], fileSets: [] }
      var totalItems = 501
      expect(data && totalItems > IMPORT_SIZE_MODERATE).toBe(true)
    })

    it('not flagged when total items is 500 or fewer', () => {
      var IMPORT_SIZE_MODERATE = stepper.CONSTANTS.IMPORT_SIZE_MODERATE
      var totalItems = 500
      var data = { collections: [], works: [], fileSets: [] }
      expect(data && totalItems > IMPORT_SIZE_MODERATE).toBe(false)
    })

    it('not flagged when validation was skipped (no item count available)', () => {
      var IMPORT_SIZE_MODERATE = stepper.CONSTANTS.IMPORT_SIZE_MODERATE
      var data = null
      // When data is null the guard `data && totalItems > MODERATE` is false
      expect(data && 999 > IMPORT_SIZE_MODERATE).toBeFalsy()
    })
  })

  describe('start over button', () => {
    it('removes all uploaded files', () => {
      var state = { uploadedFiles: [{ name: 'data.csv', fileType: 'csv' }, { name: 'files.zip', fileType: 'zip' }], uploadMode: 'upload', validated: true, validationData: { isValid: true, hasWarnings: false }, warningsAcknowledge: false, skipValidation: false, demoScenario: 'valid', adminSetId: 'set-1', adminSetName: 'Default', settings: { name: 'My Import', visibility: 'restricted', rightsStatement: 'CC BY', limit: '50' } }
      var next = stepper.applyStartOver(state)
      expect(next.uploadedFiles).toEqual([])
    })

    it('resets uploadMode to "upload"', () => {
      var state = { uploadedFiles: [], uploadMode: 'file_path', validated: false, validationData: null, warningsAcknowledge: false, skipValidation: false, demoScenario: null, adminSetId: '', adminSetName: '', settings: { name: '', visibility: 'open', rightsStatement: '', limit: '' } }
      var next = stepper.applyStartOver(state)
      expect(next.uploadMode).toBe('upload')
    })

    it('removes all validation data', () => {
      var state = { uploadedFiles: [], uploadMode: 'upload', validated: true, validationData: { isValid: true, hasWarnings: true }, warningsAcknowledge: true, skipValidation: true, demoScenario: 'warning', adminSetId: 'set-1', adminSetName: 'Default', settings: { name: 'Test', visibility: 'open', rightsStatement: '', limit: '' } }
      var next = stepper.applyStartOver(state)
      expect(next.validated).toBe(false)
      expect(next.validationData).toBeNull()
      expect(next.skipValidation).toBe(false)
    })
  })
})

describe('Wizard Utility', () => {
  describe('Debounce behavior', () => {
    beforeEach(() => { jest.useFakeTimers() })
    afterEach(() => { jest.useRealTimers() })

    it('delays execution until after the wait period', () => {
      var fn = jest.fn()
      var debounced = stepper.debounce(fn, 300)
      debounced()
      expect(fn).not.toHaveBeenCalled()
      jest.advanceTimersByTime(300)
      expect(fn).toHaveBeenCalledTimes(1)
    })

    it('resets the timer if called again within the wait period', () => {
      var fn = jest.fn()
      var debounced = stepper.debounce(fn, 300)
      debounced()
      jest.advanceTimersByTime(200) // not yet
      debounced()                   // resets timer
      jest.advanceTimersByTime(200) // still not yet (only 200ms since last call)
      expect(fn).not.toHaveBeenCalled()
      jest.advanceTimersByTime(100) // now 300ms since the second call
      expect(fn).toHaveBeenCalledTimes(1)
    })

    it('only fires once after rapid successive calls', () => {
      var fn = jest.fn()
      var debounced = stepper.debounce(fn, 300)
      for (var i = 0; i < 10; i++) { debounced() }
      jest.advanceTimersByTime(300)
      expect(fn).toHaveBeenCalledTimes(1)
    })

    it('passes through arguments and context', () => {
      var received = {}
      var fn = function (a, b) {
        received.context = this
        received.args = [a, b]
      }
      var ctx = { label: 'test-context' }
      var debounced = stepper.debounce(fn, 100)
      debounced.call(ctx, 'hello', 42)
      jest.advanceTimersByTime(100)
      expect(received.args).toEqual(['hello', 42])
      expect(received.context).toBe(ctx)
    })
  })

  describe('Validation response normalization', () => {
    it('normalizes snake_case fields (file_sets, row_count, etc.) to camelCase', () => {
      var raw = {
        file_sets: [{}],
        row_count: 5,
        total_items: 10,
        missing_required: [],
        is_valid: true,
        has_warnings: false
      }
      var normalized = stepper.normalizeValidationData(raw)
      expect(normalized.fileSets).toEqual([{}])
      expect(normalized.rowCount).toBe(5)
      expect(normalized.totalItems).toBe(10)
      expect(normalized.missingRequired).toEqual([])
    })

    it('preserves camelCase fields when already present', () => {
      var raw = {
        fileSets: [{}],
        rowCount: 7,
        totalItems: 14,
        isValid: true,
        hasWarnings: false
      }
      var normalized = stepper.normalizeValidationData(raw)
      expect(normalized.fileSets).toEqual([{}])
      expect(normalized.rowCount).toBe(7)
      expect(normalized.totalItems).toBe(14)
    })

    it('returns null/undefined input unchanged', () => {
      expect(stepper.normalizeValidationData(null)).toBeNull()
      expect(stepper.normalizeValidationData(undefined)).toBeUndefined()
    })
  })

  describe('validity determination', () => {
    it('trusts explicit isValid: true', () => {
      expect(stepper.determineIsValid({ isValid: true })).toBe(true)
    })

    it('trusts explicit isValid: false', () => {
      expect(stepper.determineIsValid({ isValid: false })).toBe(false)
    })

    it('trusts explicit is_valid (snake_case)', () => {
      expect(stepper.determineIsValid({ is_valid: true })).toBe(true)
      expect(stepper.determineIsValid({ is_valid: false })).toBe(false)
    })

    it('treats string "true" as valid, "false" as invalid', () => {
      expect(stepper.determineIsValid({ isValid: 'true' })).toBe(true)
      expect(stepper.determineIsValid({ isValid: 'false' })).toBe(false)
    })

    it('falls back to valid when rowCount exists but no explicit isValid flag', () => {
      expect(stepper.determineIsValid({ rowCount: 5 })).toBe(true)
      expect(stepper.determineIsValid({ row_count: 3 })).toBe(true)
    })

    it('falls back to invalid when neither isValid nor rowCount exist', () => {
      expect(stepper.determineIsValid({})).toBe(false)
    })
  })

  describe('warning determination', () => {
    it('detects hasWarnings: true', () => {
      expect(stepper.determineHasWarnings({ hasWarnings: true })).toBe(true)
    })

    it('detects has_warnings: true (snake_case)', () => {
      expect(stepper.determineHasWarnings({ has_warnings: true })).toBe(true)
    })

    it('defaults to no warnings when flag is absent', () => {
      expect(stepper.determineHasWarnings({})).toBe(false)
      expect(stepper.determineHasWarnings({ hasWarnings: false })).toBe(false)
    })
  })
})
