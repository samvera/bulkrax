// Bulk Import Stepper - Multi-step wizard for CSV/ZIP imports
// Handles file uploads, validation, settings, and review steps
//
// DEPENDENCIES:
// - jQuery (global)
// - BulkraxUtils (from bulkrax_utils.js - must load first)
//
// TABLE OF CONTENTS:
// - Imports from BulkraxUtils (lines 22-25)
// - Constants & Configuration (lines 27-64)
// - State Management (lines 66-87)
// - Initialization (lines 89-104)
// - Event Binding (lines 106-328)
// - File Validation & Utilities (lines 329-373)
// - File Upload Handlers (lines 374-539)
// - Demo Scenarios (lines 540-582)
// - Upload State Management (lines 583-778)
// - Validation (lines 779-935)
// - Validation Results Rendering (lines 936-1200)
// - Import Summary & Hierarchy (lines 1201-1327)
// - Settings & Navigation (lines 1328-1539)
// - Form Submission & Success State (lines 1540-1570)
// - Utility Functions (lines 1571-1603)

; (function ($, Utils) {
  'use strict'

  // Import utilities from BulkraxUtils
  var escapeHtml = Utils.escapeHtml
  var formatFileSize = Utils.formatFileSize
  var normalizeBoolean = Utils.normalizeBoolean

  // ============================================================================
  // CONSTANTS & CONFIGURATION
  // ============================================================================

  var CONSTANTS = {
    // File upload limits
    MAX_FILES: 2,
    MAX_FILE_SIZE_DISPLAY_THRESHOLD: 1024, // bytes per KB

    // Import size thresholds
    IMPORT_SIZE_OPTIMAL: 100,
    IMPORT_SIZE_MODERATE: 500,
    IMPORT_SIZE_LARGE: 1000,

    // File types
    ALLOWED_EXTENSIONS: ['.csv', '.zip'],

    // Upload states
    UPLOAD_STATES: {
      EMPTY: 'empty',
      CSV_ONLY: 'csv_only',
      ZIP_FILES_ONLY: 'zip_files_only',
      ZIP_WITH_CSV: 'zip_with_csv',
      CSV_AND_ZIP: 'csv_and_zip'
    },

    // Animation timings
    ANIMATION_SPEED: 200,
    SCROLL_SPEED: 300,
    VALIDATION_DELAY: 2000,
    NOTIFICATION_FADE_SPEED: 300,

    // AJAX timeouts (in milliseconds)
    AJAX_TIMEOUT_SHORT: 10000, // 10 seconds for simple requests
    AJAX_TIMEOUT_LONG: 60000, // 60 seconds for file uploads/validation

    // API endpoints
    ENDPOINTS: {
      DEMO_SCENARIOS: '/importers/v2/demo_scenarios',
      VALIDATE: '/importers/v2/validate'
    }
  }

  // ============================================================================
  // STATE MANAGEMENT
  // ============================================================================

  var StepperState = {
    currentStep: 1,
    uploadedFiles: [],
    uploadState: CONSTANTS.UPLOAD_STATES.EMPTY,
    validated: false,
    validationData: null,
    warningsAcked: false,
    skipValidation: false, // Flag to skip validation step
    isAddingFiles: false, // Flag to track if we're adding files vs replacing
    demoScenario: null, // Track which demo scenario is loaded
    demoScenariosData: null, // Cached demo scenarios JSON from server
    settings: {
      name: '',
      adminSetId: '',
      visibility: 'open',
      rightsStatement: '',
      limit: ''
    }
  }

  // ============================================================================
  // INITIALIZATION
  // ============================================================================

  // Initialize on page load
  function initBulkImportStepper() {
    if ($('#bulk-import-stepper-form').length === 0) {
      return
    }

    bindEvents()
    initAdminSetState()
    updateStepperUI()
    initVisibilityCards()
    setDefaultImportName()
  }

  // ============================================================================
  // EVENT BINDING
  // ============================================================================

  // Bind all event handlers
  function bindEvents() {
    // Unbind all events first to prevent memory leaks and duplicate handlers
    // This is critical since initBulkImportStepper runs on both 'ready' and 'turbolinks:load'

    // File upload - main dropzone
    $('.upload-dropzone').off('click').on('click', function (e) {
      if (e.target.id === 'file-input') return

      StepperState.isAddingFiles = false
      $('#file-input').trigger('click')
    })

    // File upload - add another dropzone
    $('.upload-dropzone-small').off('click').on('click', function () {
      StepperState.isAddingFiles = true
      $('#file-input').trigger('click')
    })

    $('#file-input').off('change').on('change', function () {
      handleFileSelect(StepperState.isAddingFiles)
      StepperState.isAddingFiles = false // Reset flag after handling
    })

    // Drag and drop - main dropzone
    $('.upload-dropzone').off('dragover').on('dragover', function (e) {
      e.preventDefault()
      $(this).addClass('dragover')
    })

    $('.upload-dropzone').off('dragleave').on('dragleave', function (e) {
      e.preventDefault()
      $(this).removeClass('dragover')
    })

    $('.upload-dropzone').off('drop').on('drop', function (e) {
      e.preventDefault()
      $(this).removeClass('dragover')
      var droppedFiles = e.originalEvent.dataTransfer.files
      if (droppedFiles.length > 0) {
        // Prepare files array (up to MAX_FILES total)
        var maxFiles = Math.min(droppedFiles.length, CONSTANTS.MAX_FILES)
        var filesToAdd = []
        for (var i = 0; i < maxFiles; i++) {
          filesToAdd.push(droppedFiles[i])
        }

        // Try to set files on input element (with browser compatibility fallback)
        setInputFiles($('#file-input')[0], filesToAdd)

        // Set flag based on whether we already have files
        StepperState.isAddingFiles = false // Drag and drop replaces files

        handleFileSelect(StepperState.isAddingFiles)
        StepperState.isAddingFiles = false

        // Show warning if more than MAX_FILES were dropped
        if (droppedFiles.length > CONSTANTS.MAX_FILES) {
          showNotification(
            'Only the first ' + CONSTANTS.MAX_FILES + ' files have been uploaded. You can upload up to ' + CONSTANTS.MAX_FILES + ' files (1 CSV and 1 ZIP).'
          )
        }
      }
    })

    // Drag and drop - small "add another" dropzone
    $('.upload-dropzone-small').off('dragover').on('dragover', function (e) {
      e.preventDefault()
      $(this).addClass('dragover')
    })

    $('.upload-dropzone-small').off('dragleave').on('dragleave', function (e) {
      e.preventDefault()
      $(this).removeClass('dragover')
    })

    $('.upload-dropzone-small').off('drop').on('drop', function (e) {
      e.preventDefault()
      $(this).removeClass('dragover')
      var droppedFiles = e.originalEvent.dataTransfer.files
      if (droppedFiles.length > 0) {
        // Add only 1 file since we're adding to existing
        var filesToAdd = [droppedFiles[0]]

        // Try to set files on input element (with browser compatibility fallback)
        setInputFiles($('#file-input')[0], filesToAdd)

        // Set flag to indicate we're adding files
        StepperState.isAddingFiles = true

        handleFileSelect(StepperState.isAddingFiles)
        StepperState.isAddingFiles = false

        // Show warning if more than 1 file was dropped
        if (droppedFiles.length > 1) {
          showNotification(
            'Only 1 additional file can be added. The first file has been added.'
          )
        }
      }
    })

    // Demo scenarios (for testing)
    $('.step-circle').off('dblclick').on('dblclick', function () {
      var $panel = $('.demo-scenarios')
      $panel.toggle()
      if ($panel.is(':visible')) {
        loadDemoScenariosData(function () { }) // Prefetch
      }
    })

    $('.scenario-btn').off('click').on('click', function () {
      var scenario = $(this).data('scenario')
      loadDemoScenario(scenario)
      $('.demo-scenarios').hide()
    })

    // Start over
    $('#start-over-btn').off('click').on('click', function () {
      resetUploadState()
    })

    // Start over
    $('#upload-different-btn').off('click').on('click', function (e) {
      e.preventDefault()
      resetUploadState()
    })

    // Validate button
    $('#validate-btn').off('click').on('click', function () {
      validateFiles()
    })

    // Warnings acknowledgment
    $('#warnings-acked').off('change').on('change', function () {
      StepperState.warningsAcked = $(this).is(':checked')
      updateStepNavigation()
    })

    // Step navigation
    $('.step-next-btn').off('click').on('click', function () {
      var nextStep = parseInt($(this).data('next-step'))
      goToStep(nextStep)
    })

    $('.step-prev-btn').off('click').on('click', function () {
      var prevStep = parseInt($(this).data('prev-step'))
      goToStep(prevStep)
    })

    // Form submission
    $('#bulk-import-stepper-form').off('submit').on('submit', function (e) {
      e.preventDefault()
      handleImportSubmit()
    })

    // Start another import
    $('#start-another-import').off('click').on('click', function () {
      location.reload()
    })

    // Settings form changes
    $('#bulkrax_importer_name').off('input').on('input', function () {
      StepperState.settings.name = $(this).val()
      updateStepNavigation()
    })

    $('#importer_admin_set_id').off('change').on('change', function () {
      StepperState.settings.adminSetId = $(this).val()
      StepperState.settings.adminSetName = $(this).find('option:selected').text()
      updateStepNavigation()
      // Update validate button state since admin set is required for validation
      if (StepperState.uploadedFiles.length > 0) {
        renderUploadedFiles()
      }
    })

    $('#bulkrax_importer_limit').off('input').on('input', function () {
      StepperState.settings.limit = $(this).val()
    })

    // Remove file button (using event delegation since rows are dynamic)
    $(document).off('click', '.file-remove-btn').on('click', '.file-remove-btn', function () {
      var $row = $(this).closest('.file-row')
      var fileName = $row.find('.file-name').text()

      // Remove from uploadedFiles array
      StepperState.uploadedFiles = StepperState.uploadedFiles.filter(
        file => file.name !== fileName
      )

      // Remove the row
      $row.remove()
      $('#file-input').val('')

      // If no files left, reset to empty state
      if (StepperState.uploadedFiles.length === 0) {
        StepperState.validated = false
        StepperState.validationData = null
        StepperState.skipValidation = false
        $('.validation-results').hide()
        $('.warning-acknowledgment').hide()
        $('#validate-btn')
          .prop('disabled', true)
          .html('<span class="fa fa-file-text"></span> Validate Files')
        $('#skip-validation-checkbox').prop('checked', false)
      }

      // Update upload state and re-render
      updateUploadState()
      renderUploadedFiles()
      updateStepNavigation()
    })

    // Skip validation checkbox
    $('#skip-validation-checkbox').off('change').on('change', function () {
      StepperState.skipValidation = $(this).is(':checked')
      updateStepNavigation()
    })
  }

  // ============================================================================
  // FILE VALIDATION & UTILITIES
  // ============================================================================

  // Check if DataTransfer is supported (not available in older Safari)
  function isDataTransferSupported() {
    try {
      return typeof DataTransfer !== 'undefined' && typeof DataTransfer === 'function'
    } catch (e) {
      return false
    }
  }

  // Helper to set files on input element with browser compatibility
  function setInputFiles(inputElement, files) {
    if (isDataTransferSupported()) {
      var dataTransfer = new DataTransfer()
      for (var i = 0; i < files.length; i++) {
        dataTransfer.items.add(files[i])
      }
      inputElement.files = dataTransfer.files
      return true
    } else {
      // Fallback for older browsers: can't set files property
      // Return false to indicate files weren't set on input
      console.warn('DataTransfer not supported - files will be processed from memory')
      return false
    }
  }

  // Get file extension (lowercase)
  function getFileExtension(filename) {
    var lastDot = filename.lastIndexOf('.')
    if (lastDot === -1) return ''
    return filename.substring(lastDot).toLowerCase()
  }

  // Validate file extension
  function isValidFileType(filename) {
    var ext = getFileExtension(filename)
    return CONSTANTS.ALLOWED_EXTENSIONS.indexOf(ext) !== -1
  }

  // Show inline error messages
  function showFileUploadError(messages) {
    var errorContainer = $('#file-upload-errors')
    if (messages && messages.length > 0) {
      var html = '<div class="alert alert-danger alert-dismissible" role="alert">'
      html += '<button type="button" class="close" data-dismiss="alert" aria-label="Close">'
      html += '<span aria-hidden="true">&times;</span>'
      html += '</button>'
      html += '<strong><span class="fa fa-exclamation-circle"></span> File Upload Error</strong>'
      html += '<ul class="mb-0 mt-2">'
      messages.forEach(function (msg) {
        // Escape the message but allow intentional <br> tags for newlines
        var escapedMsg = escapeHtml(msg).replace(/\n/g, '<br>')
        html += '<li>' + escapedMsg + '</li>'
      })
      html += '</ul>'
      html += '</div>'
      errorContainer.html(html).show()
    } else {
      errorContainer.hide().html('')
    }
  }

  // Clear file upload errors
  function clearFileUploadError() {
    $('#file-upload-errors').hide().html('')
  }

  // ============================================================================
  // FILE UPLOAD HANDLERS
  // ============================================================================

  // Handle file selection
  function handleFileSelect(isAddingMore) {
    var files = $('#file-input')[0].files
    if (files.length === 0) return

    // If not adding more, reset the uploaded files array
    if (!isAddingMore) {
      StepperState.uploadedFiles = []
    }

    // Count existing file types
    var existingCsvCount = StepperState.uploadedFiles.filter(function (f) {
      return f.fileType === 'csv' && !f.fromZip
    }).length
    var existingZipCount = StepperState.uploadedFiles.filter(function (f) {
      return f.fileType === 'zip'
    }).length

    var addedFiles = []
    var rejectedFiles = []

    // Process selected files with validation
    for (
      var i = 0;
      i < files.length && StepperState.uploadedFiles.length < CONSTANTS.MAX_FILES;
      i++
    ) {
      var file = files[i]
      var fileName = file.name
      var fileSize = formatFileSize(file.size)

      // Validate file extension first
      if (!isValidFileType(fileName)) {
        rejectedFiles.push({
          name: fileName,
          reason: 'invalid_type',
          extension: getFileExtension(fileName)
        })
        continue
      }

      var fileType = fileName.endsWith('.csv') ? 'csv' : 'zip'

      // Check for duplicates
      var isDuplicate = StepperState.uploadedFiles.some(function (f) {
        return f.name === fileName
      })

      if (isDuplicate) {
        rejectedFiles.push({ name: fileName, reason: 'duplicate' })
        continue
      }

      // Validate file type constraints (max 1 CSV, max 1 ZIP)
      if (fileType === 'csv' && existingCsvCount >= 1) {
        rejectedFiles.push({ name: fileName, reason: 'duplicate CSV' })
        continue
      }

      if (fileType === 'zip' && existingZipCount >= 1) {
        rejectedFiles.push({ name: fileName, reason: 'duplicate ZIP' })
        continue
      }

      // Add the file
      StepperState.uploadedFiles.push({
        id: Date.now() + i,
        name: fileName,
        size: fileSize,
        fileType: fileType,
        fromZip: false,
        file: file
      })

      addedFiles.push(fileName)

      // Update counts
      if (fileType === 'csv') existingCsvCount++
      if (fileType === 'zip') existingZipCount++
    }

    // Show appropriate warnings
    if (rejectedFiles.length > 0) {
      var messages = []

      // Handle invalid file types FIRST
      var invalidTypes = rejectedFiles.filter(function (f) {
        return f.reason === 'invalid_type'
      })

      if (invalidTypes.length > 0) {
        messages.push(
          'Invalid file format. Only .csv and .zip files are allowed.\n' +
          'The following files were rejected:\n• ' +
          invalidTypes.map(function (f) {
            return f.name + ' (' + (f.extension || 'no extension') + ')'
          }).join('\n• ')
        )
      }

      var duplicateCsv = rejectedFiles.filter(function (f) {
        return f.reason === 'duplicate CSV'
      })
      var duplicateZip = rejectedFiles.filter(function (f) {
        return f.reason === 'duplicate ZIP'
      })
      var duplicates = rejectedFiles.filter(function (f) {
        return f.reason === 'duplicate'
      })

      if (duplicateCsv.length > 0) {
        messages.push(
          'Only 1 CSV file allowed. The following files were not added:\n• ' +
          duplicateCsv
            .map(function (f) {
              return f.name
            })
            .join('\n• ')
        )
      }
      if (duplicateZip.length > 0) {
        messages.push(
          'Only 1 ZIP file allowed. The following files were not added:\n• ' +
          duplicateZip
            .map(function (f) {
              return f.name
            })
            .join('\n• ')
        )
      }
      if (duplicates.length > 0) {
        messages.push(
          'The following files were already uploaded:\n• ' +
          duplicates
            .map(function (f) {
              return f.name
            })
            .join('\n• ')
        )
      }
      if (
        StepperState.uploadedFiles.length >= CONSTANTS.MAX_FILES &&
        files.length > addedFiles.length + rejectedFiles.length
      ) {
        messages.push('Maximum of ' + CONSTANTS.MAX_FILES + ' files reached (1 CSV and 1 ZIP).')
      }

      showFileUploadError(messages)
    } else if (files.length > addedFiles.length) {
      showFileUploadError([
        'Maximum of ' + CONSTANTS.MAX_FILES + ' files allowed (1 CSV and 1 ZIP). Only the first ' +
        addedFiles.length +
        ' file(s) were added.'
      ])
    } else {
      clearFileUploadError()
    }

    updateUploadState()
    renderUploadedFiles()
  }

  // ============================================================================
  // DEMO SCENARIOS
  // ============================================================================

  // Fetch and cache demo scenarios JSON from server
  function loadDemoScenariosData(callback) {
    if (StepperState.demoScenariosData) {
      callback(StepperState.demoScenariosData)
      return
    }

    $.ajax({
      url: CONSTANTS.ENDPOINTS.DEMO_SCENARIOS,
      method: 'GET',
      dataType: 'json',
      timeout: CONSTANTS.AJAX_TIMEOUT_SHORT,
      success: function (data) {
        StepperState.demoScenariosData = data
        callback(data)
      },
      error: function (xhr, status, error) {
        var errorMsg = 'Failed to load demo scenarios'
        if (status === 'timeout') {
          errorMsg = 'Request timed out while loading demo scenarios'
        } else if (status === 'error' && xhr.status === 0) {
          errorMsg = 'Network error - please check your connection'
        } else if (xhr.status >= 500) {
          errorMsg = 'Server error while loading demo scenarios'
        }
        console.warn(errorMsg, { status: status, error: error, statusCode: xhr.status })
        showNotification(errorMsg, 'error')
        callback(null)
      }
    })
  }

  // Load demo scenario from cached JSON
  function loadDemoScenario(scenario) {
    resetUploadState()

    loadDemoScenariosData(function (data) {
      if (!data || !data.scenarios || !data.scenarios[scenario]) {
        console.warn('Demo scenario not found:', scenario)
        return
      }

      StepperState.uploadedFiles = data.scenarios[scenario].files
      StepperState.demoScenario = scenario
      updateUploadState()
      renderUploadedFiles()
    })
  }

  // ============================================================================
  // UPLOAD STATE MANAGEMENT
  // ============================================================================

  // Update upload state based on files
  function updateUploadState() {
    var files = StepperState.uploadedFiles
    if (files.length === 0) {
      StepperState.uploadState = CONSTANTS.UPLOAD_STATES.EMPTY
      return
    }

    var hasStandaloneCsv = files.some(function (f) {
      return f.fileType === 'csv' && !f.fromZip
    })
    var hasZip = files.some(function (f) {
      return f.fileType === 'zip'
    })
    var hasCsvInZip = files.some(function (f) {
      return f.fileType === 'csv' && f.fromZip
    })

    if (hasZip && hasCsvInZip && !hasStandaloneCsv) {
      StepperState.uploadState = CONSTANTS.UPLOAD_STATES.ZIP_WITH_CSV
    } else if (hasZip && !hasCsvInZip && !hasStandaloneCsv) {
      StepperState.uploadState = CONSTANTS.UPLOAD_STATES.ZIP_FILES_ONLY
    } else if (hasStandaloneCsv && hasZip) {
      StepperState.uploadState = CONSTANTS.UPLOAD_STATES.CSV_AND_ZIP
    } else if (hasStandaloneCsv && !hasZip) {
      StepperState.uploadState = CONSTANTS.UPLOAD_STATES.CSV_ONLY
    } else {
      StepperState.uploadState = CONSTANTS.UPLOAD_STATES.EMPTY
    }
  }

  // Render uploaded files
  function renderUploadedFiles() {
    // Ensure admin set state is captured (handles timing issues)
    // Always refresh from DOM to ensure we have the current value
    var $adminSetSelect = $('#importer_admin_set_id')
    if ($adminSetSelect.length && $adminSetSelect.val()) {
      StepperState.settings.adminSetId = $adminSetSelect.val()
      StepperState.settings.adminSetName = $adminSetSelect.find('option:selected').text()
    }

    var state = StepperState.uploadState
    var files = StepperState.uploadedFiles

    if (state === CONSTANTS.UPLOAD_STATES.EMPTY) {
      $('.upload-zone-empty').show()
      $('.uploaded-files-container').hide()
      $('.add-another-dropzone').hide()
      $('.start-over-link').hide()
      $('#validate-btn').prop('disabled', true)
      $('#skip-validation-checkbox').prop('disabled', true) // Disable checkbox when empty
      return
    }

    $('.upload-zone-empty').hide()
    $('.uploaded-files-container').show()

    var $list = $('.uploaded-files-list')
    $list.empty()

    var hasCsv = files.some(function (f) {
      return f.fileType === 'csv'
    })
    var hasZip = files.some(function (f) {
      return f.fileType === 'zip'
    })

    // Render all uploaded files
    files.forEach(function (file) {
      var subtitle = file.subtitle || file.size
      $list.append(renderFileRow(file.fileType, file.name, subtitle, true))
    })

    // Show appropriate info message based on state
    var infoMessage = ''
    if (state === CONSTANTS.UPLOAD_STATES.ZIP_WITH_CSV) {
      infoMessage =
        '<div class="upload-info"><span class="fa fa-info-circle"></span> Single package with CSV and files</div>'
    } else if (state === CONSTANTS.UPLOAD_STATES.CSV_ONLY) {
      infoMessage =
        '<div class="upload-info"><span class="fa fa-info-circle"></span> No ZIP uploaded — files will be matched from server paths or you can add more files</div>'
    } else if (state === CONSTANTS.UPLOAD_STATES.ZIP_FILES_ONLY) {
      infoMessage =
        '<div class="upload-info"><span class="fa fa-info-circle"></span> ZIP file uploaded — validation will check for CSV content</div>'
    } else if (state === CONSTANTS.UPLOAD_STATES.CSV_AND_ZIP) {
      infoMessage =
        '<div class="upload-info"><span class="fa fa-info-circle"></span> CSV + files uploaded separately</div>'
    }

    $('.upload-info-message').html(infoMessage)

    // Show file count if multiple files
    if (files.length > 1) {
      $('.uploaded-files-header strong').text(
        'Uploaded Files (' + files.length + ')'
      )
    } else {
      $('.uploaded-files-header strong').text('Uploaded File')
    }

    // Show/hide "Add another file" dropzone based on file count
    if (files.length === 1) {
      $('.add-another-dropzone').show()
      $('.start-over-link').show()
    } else if (files.length >= 2) {
      $('.add-another-dropzone').hide()
      $('.start-over-link').show()
    } else {
      $('.add-another-dropzone').hide()
      $('.start-over-link').hide()
    }

    // Enable validate button if we have a CSV OR a ZIP file (which might contain a CSV) AND an admin set is selected
    var adminSetValue = $('#importer_admin_set_id').val() || StepperState.settings.adminSetId
    var hasAdminSet = adminSetValue && adminSetValue.length > 0
    $('#validate-btn').prop(
      'disabled',
      !(hasCsv || hasZip) || !hasAdminSet || StepperState.validated
    )

    // Enable skip validation checkbox only if we have a CSV or ZIP
    $('#skip-validation-checkbox').prop('disabled', !(hasCsv || hasZip))
  }

  // Render a single file row
  function renderFileRow(type, name, subtitle, verified) {
    var icon = type === 'csv' ? 'fa-file-text' : 'fa-file-archive-o'
    var iconBg = type === 'csv' ? 'file-icon-csv' : 'file-icon-zip'
    var checkmark = verified
      ? '<span class="fa fa-check-circle file-verified"></span>'
      : ''

    // Escape user-provided data (file name and subtitle)
    var safeName = escapeHtml(name)
    var safeSubtitle = escapeHtml(subtitle)

    return (
      '<div class="file-row">' +
      '<div class="file-info">' +
      '<div class="file-icon ' +
      iconBg +
      '"><span class="fa ' +
      icon +
      '"></span></div>' +
      '<div class="file-details">' +
      '<div class="file-name">' +
      safeName +
      '</div>' +
      '<div class="file-subtitle">' +
      safeSubtitle +
      '</div>' +
      '</div>' +
      '</div>' +
      '<div class="file-actions">' +
      checkmark +
      '<button type="button" class="file-remove-btn" aria-label="Remove file">' +
      '<span class="fa fa-times"></span>' +
      '</button>' +
      '</div>' +
      '</div>'
    )
  }

  // Reset upload state
  function resetUploadState() {
    StepperState.uploadedFiles = []
    StepperState.uploadState = CONSTANTS.UPLOAD_STATES.EMPTY
    StepperState.validated = false
    StepperState.validationData = null
    StepperState.warningsAcked = false
    StepperState.skipValidation = false
    StepperState.demoScenario = null
    $('#file-input').val('')
    $('.validation-results').hide()
    $('.warning-acknowledgment').hide()
    clearFileUploadError()

    // Clear all notifications
    $('#upload-notifications').empty()

    // Reset skip validation checkbox
    $('#skip-validation-checkbox').prop('checked', false)

    // Reset validate button to original state
    $('#validate-btn')
      .prop('disabled', true)
      .html('<span class="fa fa-file-text"></span> Validate Files')

    renderUploadedFiles()
    updateStepNavigation()
  }

  // ============================================================================
  // VALIDATION
  // ============================================================================

  // Validate files (AJAX call to backend)
  function validateFiles() {
    var $btn = $('#validate-btn')
    $btn
      .prop('disabled', true)
      .html('<span class="fa fa-spinner fa-spin"></span> Validating...')

    // Check if we're in demo mode (no real file selected)
    var fileInput = $('#file-input')[0]
    var useMockData =
      !fileInput || !fileInput.files || fileInput.files.length === 0

    if (useMockData) {
      // Use mock data for demo scenarios
      setTimeout(function () {
        var mockData = getMockValidationData()
        if (!mockData) {
          showNotification('Demo data not loaded. Try selecting a scenario again.', 'error')
          $btn
            .prop('disabled', false)
            .html('<span class="fa fa-file-text"></span> Validate Files')
          return
        }
        StepperState.validated = true
        StepperState.validationData = normalizeValidationData(mockData)

        renderValidationResults(StepperState.validationData)
        $btn.html('<span class="fa fa-check-circle"></span> Validated')
        updateStepNavigation()
      }, CONSTANTS.VALIDATION_DELAY)
    } else {
      // Real AJAX call for actual file uploads
      var formData = new FormData($('#bulk-import-stepper-form')[0])

      $.ajax({
        url: CONSTANTS.ENDPOINTS.VALIDATE,
        method: 'POST',
        data: formData,
        processData: false,
        contentType: false,
        timeout: CONSTANTS.AJAX_TIMEOUT_LONG,
        success: function (data) {
          var normalized = normalizeValidationData(data)
          StepperState.validated = true
          StepperState.validationData = normalized
          try {
            renderValidationResults(normalized)
          } catch (e) {
            console.error('Validation results render issue:', e)
            StepperState.validated = false
            StepperState.validationData = null
            showNotification('Validation completed but results could not be displayed. Please try again.', 'error')
            $btn.prop('disabled', false).html('<span class="fa fa-file-text"></span> Validate Files')
            return
          }
          $btn.html('<span class="fa fa-check-circle"></span> Validated')
          updateStepNavigation()
        },
        error: function (xhr, status, error) {
          var errorMsg = 'Validation failed. Please try again.'

          // Handle specific error cases
          if (status === 'timeout') {
            errorMsg = 'Validation timed out. Your files may be too large. Please try with smaller files or contact support.'
          } else if (status === 'error' && xhr.status === 0) {
            errorMsg = 'Network error - please check your connection and try again.'
          } else if (xhr.status === 413) {
            errorMsg = 'Files are too large. Please reduce file size and try again.'
          } else if (xhr.status === 422) {
            errorMsg = xhr.responseJSON && xhr.responseJSON.error
              ? xhr.responseJSON.error
              : 'Invalid file format. Please check your files and try again.'
          } else if (xhr.status >= 500) {
            errorMsg = 'Server error during validation. Please try again or contact support.'
          } else if (xhr.responseJSON && xhr.responseJSON.error) {
            errorMsg = xhr.responseJSON.error
          }

          console.error('Validation error:', {
            status: status,
            error: error,
            statusCode: xhr.status,
            response: xhr.responseJSON
          })

          showNotification(errorMsg, 'error')

          // Reset button state
          $btn
            .prop('disabled', false)
            .html('<span class="fa fa-file-text"></span> Validate Files')

          // Reset validation state on error
          StepperState.validated = false
          StepperState.validationData = null
        }
      })
    }
  }

  // Helper: Determine if validation data indicates valid state
  function determineIsValid(data) {
    // Check both camelCase and snake_case property names
    var isValidValue = normalizeBoolean(data.isValid != null ? data.isValid : data.is_valid)

    // If explicitly set to true or false, use that value
    if (isValidValue !== null) {
      return isValidValue
    }

    // Fallback: If we have row data but no explicit validity flag,
    // assume valid (backend processed without marking as invalid)
    var hasRowData = data.rowCount != null || data.row_count != null
    return hasRowData
  }

  // Helper: Determine if validation has warnings
  function determineHasWarnings(data) {
    var hasWarningsValue = normalizeBoolean(
      data.hasWarnings != null ? data.hasWarnings : data.has_warnings
    )
    return hasWarningsValue === true
  }

  function normalizeValidationData(data) {
    if (!data) return data
    return {
      collections: data.collections,
      works: data.works,
      fileSets: data.fileSets || data.file_sets,
      totalItems: data.totalItems != null ? data.totalItems : data.total_items,
      headers: data.headers,
      missingRequired: data.missingRequired || data.missing_required,
      unrecognized: data.unrecognized,
      rowCount: data.rowCount != null ? data.rowCount : data.row_count,
      isValid: determineIsValid(data),
      hasWarnings: determineHasWarnings(data),
      fileReferences: data.fileReferences != null ? data.fileReferences : data.file_references,
      missingFiles: data.missingFiles || data.missing_files,
      foundFiles: data.foundFiles != null ? data.foundFiles : data.found_files,
      zipIncluded: data.zipIncluded != null ? data.zipIncluded : data.zip_included,
      messages: data.messages
    }
  }

  // Normalize childrenIds into parentIds and build a hierarchy lookup map.
  // This converts parent-declares-children relationships into the canonical
  // child-declares-parent form, then pre-computes a map for O(1) hierarchy lookups.
  function normalizeRelationships(data) {
    var allItems = data.collections.concat(data.works)

    // Build id -> item lookup
    var itemMap = {}
    allItems.forEach(function (item) {
      if (!item.parentIds) { item.parentIds = [] }
      itemMap[item.id] = item
    })

    // Convert childrenIds into parentIds on each referenced child item
    allItems.forEach(function (item) {
      if (item.childrenIds && item.childrenIds.length > 0) {
        item.childrenIds.forEach(function (childId) {
          var child = itemMap[childId]
          if (child && child.parentIds.indexOf(item.id) === -1) {
            child.parentIds.push(item.id)
          }
        })
      }
    })

    // Build hierarchy lookup map from normalized parentIds
    var hierarchyMap = {}
    allItems.forEach(function (item) {
      item.parentIds.forEach(function (parentId) {
        if (!hierarchyMap[parentId]) { hierarchyMap[parentId] = [] }
        hierarchyMap[parentId].push(item)
      })
    })

    return hierarchyMap
  }

  // ============================================================================
  // VALIDATION RESULTS RENDERING
  // ============================================================================

  // Render validation results
  function renderValidationResults(data) {
    $('.validation-results').show()

    // Normalize childrenIds -> parentIds and build hierarchy lookup map
    var hierarchyMap = normalizeRelationships(data)

    // Import size gauge
    renderImportSizeGauge(data.totalItems)

    // Validation status accordion
    renderValidationAccordions(data)

    // Import summary
    renderImportSummary(data, hierarchyMap)

    // Warning acknowledgment
    if (data.hasWarnings) {
      $('.warning-acknowledgment').show()
    }
  }

  // Render import size gauge
  function renderImportSizeGauge(count) {
    var pct, color, zone, msg, cardClass

    if (count <= CONSTANTS.IMPORT_SIZE_OPTIMAL) {
      pct = (count / CONSTANTS.IMPORT_SIZE_OPTIMAL) * 33
      color = 'gauge-marker-optimal'
      zone = 'Optimal'
      msg = 'Great! Smaller imports are easier to validate and troubleshoot.'
      cardClass = 'gauge-card-optimal'
    } else if (count <= CONSTANTS.IMPORT_SIZE_MODERATE) {
      pct = 33 + ((count - CONSTANTS.IMPORT_SIZE_OPTIMAL) / (CONSTANTS.IMPORT_SIZE_MODERATE - CONSTANTS.IMPORT_SIZE_OPTIMAL)) * 33
      color = 'gauge-marker-moderate'
      zone = 'Moderate'
      msg =
        'Consider splitting into smaller batches for easier error resolution.'
      cardClass = 'gauge-card-moderate'
    } else {
      pct = Math.min(66 + ((count - CONSTANTS.IMPORT_SIZE_MODERATE) / CONSTANTS.IMPORT_SIZE_MODERATE) * 34, 100)
      color = 'gauge-marker-large'
      zone = 'Large'
      msg =
        'Large imports take longer and are harder to debug. We strongly recommend splitting into batches of ' + CONSTANTS.IMPORT_SIZE_OPTIMAL + ' or fewer.'
      cardClass = 'gauge-card-large'
    }

    var html =
      '<div class="gauge-card ' +
      cardClass +
      '">' +
      '<div class="gauge-header">' +
      '<span>Import Size: ' +
      count +
      ' items</span>' +
      '<span class="gauge-zone">' +
      zone +
      '</span>' +
      '</div>' +
      '<div class="gauge-track">' +
      '<div class="gauge-segment gauge-segment-optimal"></div>' +
      '<div class="gauge-segment gauge-segment-moderate"></div>' +
      '<div class="gauge-segment gauge-segment-large"></div>' +
      '<div class="gauge-marker ' +
      color +
      '" style="left: ' +
      pct +
      '%"></div>' +
      '</div>' +
      '<div class="gauge-labels">' +
      '<span>0</span><span>' + CONSTANTS.IMPORT_SIZE_OPTIMAL + '</span><span>' + CONSTANTS.IMPORT_SIZE_MODERATE + '</span><span>' + CONSTANTS.IMPORT_SIZE_LARGE + '+</span>' +
      '</div>' +
      '<p class="gauge-message">' +
      msg +
      '</p>' +
      '</div>'

    $('.import-size-gauge').html(html)
  }

  // Group items by model for missing required fields
  function groupItemsByModel(items) {
    var grouped = {}
    items.forEach(function (item) {
      var modelName = item.model || 'Unknown'
      if (!grouped[modelName]) {
        grouped[modelName] = []
      }
      grouped[modelName].push(item.field)
    })
    return grouped
  }

  // Render missing required fields grouped by model
  function renderMissingRequiredFields(items) {
    var html = ''
    var groupedByModel = groupItemsByModel(items)

    Object.keys(groupedByModel).forEach(function (modelName) {
      html += '<div class="missing-field-group">'
      html += '<strong class="missing-field-model">' + modelName + '</strong>'
      html += '<ul>'
      groupedByModel[modelName].forEach(function (field) {
        html += '<li>• ' + field + '</li>'
      })
      html += '</ul>'
      html += '</div>'
    })

    return html
  }

  // Render default issue items (unrecognized fields, file references, etc.)
  function renderDefaultIssueItems(items) {
    var html = '<ul>'
    items.forEach(function (item) {
      var msg = item.message ? ' — ' + item.message : ''
      html += '<li>• ' + item.field + msg + '</li>'
    })
    html += '</ul>'
    return html
  }

  // Render issue items based on issue type
  function renderIssueItems(issue) {
    var hasModelField = issue.items.some(function (item) { return item.model })

    if (issue.type === 'missing_required_fields' && hasModelField) {
      return renderMissingRequiredFields(issue.items)
    } else {
      return renderDefaultIssueItems(issue.items)
    }
  }

  // Render validation accordions
  function renderValidationAccordions(data) {
    var $wrapper = $('.accordion-wrapper')
    $wrapper.empty()

    // Check if we have the new messages structure
    if (!data.messages || !data.messages.validationStatus) {
      console.error('Invalid validation response: missing messages structure')
      return
    }

    // Main validation status - FROM BACKEND
    var status = data.messages.validationStatus
    var content = '<p>' + status.summary + '</p>'
    if (status.details) {
      content += '<p class="text-muted small">' + status.details + '</p>'
    }

    $wrapper.append(
      createAccordion(
        status.title,
        status.icon,
        status.severity,
        null,
        status.defaultOpen,
        content
      )
    )

    // Render all issues - FROM BACKEND
    // Each issue uses its own severity for independent coloring
    if (data.messages.issues && data.messages.issues.length > 0) {
      data.messages.issues.forEach(function (issue) {
        var content = ''

        if (issue.description) {
          content += '<p>' + issue.description + '</p>'
        }

        if (issue.summary) {
          content += '<p>' + issue.summary + '</p>'
        }

        if (issue.items && issue.items.length > 0) {
          content += renderIssueItems(issue)
        }

        if (issue.details) {
          content += '<p class="small">' + issue.details + '</p>'
        }

        $wrapper.append(
          createAccordion(
            issue.title,
            issue.icon,
            issue.severity,
            issue.count,
            issue.defaultOpen,
            content
          )
        )
      })
    }

    bindAccordionEvents()
  }

  // Create accordion HTML
  function createAccordion(title, icon, variant, count, defaultOpen, content) {
    var variantClass = 'accordion-' + variant
    var openClass = defaultOpen ? 'accordion-open' : ''
    var contentDisplay = defaultOpen ? 'block' : 'none'
    var chevron = defaultOpen ? 'fa-chevron-down' : 'fa-chevron-right'
    var countBadge =
      count !== null ? '<span class="accordion-count">' + count + '</span>' : ''

    return (
      '<div class="accordion-item ' +
      variantClass +
      ' ' +
      openClass +
      '">' +
      '<div class="accordion-header">' +
      '<div class="accordion-title-bar">' +
      '<span class="fa ' +
      icon +
      ' accordion-status-icon"></span>' +
      '<span>' +
      title +
      '</span>' +
      countBadge +
      '</div>' +
      '<span class="fa ' +
      chevron +
      ' accordion-chevron"></span>' +
      '</div>' +
      '<div class="accordion-content" style="display: ' +
      contentDisplay +
      '">' +
      content +
      '</div>' +
      '</div>'
    )
  }

  // Bind accordion toggle events
  function bindAccordionEvents() {
    $('.accordion-header')
      .off('click')
      .on('click', function () {
        var $item = $(this).closest('.accordion-item')
        var $content = $item.find('.accordion-content')
        var $chevron = $item.find('.accordion-chevron')

        if ($item.hasClass('accordion-open')) {
          $content.slideUp(CONSTANTS.ANIMATION_SPEED)
          $chevron.removeClass('fa-chevron-down').addClass('fa-chevron-right')
          $item.removeClass('accordion-open')
        } else {
          $content.slideDown(CONSTANTS.ANIMATION_SPEED)
          $chevron.removeClass('fa-chevron-right').addClass('fa-chevron-down')
          $item.addClass('accordion-open')
        }
      })
  }

  // ============================================================================
  // IMPORT SUMMARY & HIERARCHY
  // ============================================================================

  // Render import summary
  function renderImportSummary(data, hierarchyMap) {
    $('.summary-card-collections .summary-number').text(data.collections.length)
    $('.summary-card-works .summary-number').text(data.works.length)
    $('.summary-card-filesets .summary-number').text(data.fileSets.length)

    // Hierarchy accordions
    var $container = $('.hierarchy-accordions')
    $container.empty()

    // Import hierarchy — collections, nested items, and standalone works in one tree
    var topLevelCollections = data.collections.filter(function (c) {
      return !c.parentIds || c.parentIds.length === 0
    })
    var orphanWorks = data.works.filter(function (w) {
      return !w.parentIds || w.parentIds.length === 0
    })
    var hierarchyContent =
      '<div class="hierarchy-tree">' +
      topLevelCollections
        .map(function (c) {
          return renderTreeItem(c, hierarchyMap)
        })
        .join('') +
      orphanWorks
        .map(function (w) {
          return renderTreeItem(w, hierarchyMap)
        })
        .join('') +
      '</div>'
    var itemCount = data.collections.length + data.works.length
    $container.append(
      createAccordion(
        'Import Hierarchy',
        'fa-sitemap',
        'info',
        itemCount,
        false,
        hierarchyContent
      )
    )

    bindAccordionEvents()
    bindTreeEvents()
  }

  // Render tree item using pre-computed hierarchyMap for O(1) lookups
  function renderTreeItem(item, hierarchyMap, depth) {
    depth = depth || 0
    var children = hierarchyMap[item.id] || []
    var hasChildren = children.length > 0
    var icon = item.type === 'collection' ? 'fa-folder' : 'fa-file-o'
    var iconColor = item.type === 'collection' ? 'text-primary' : 'text-muted'
    var chevron = hasChildren
      ? '<span class="fa fa-chevron-right tree-chevron"></span>'
      : '<span class="tree-spacer"></span>'
    var count = hasChildren
      ? ' <span class="text-muted small">(' + children.length + ')</span>'
      : ''
    var paddingLeft = depth * 20

    // Escape user-provided data
    var safeId = escapeHtml(item.id)
    var safeTitle = escapeHtml(item.title)

    var html =
      '<div class="tree-item" data-item-id="' +
      safeId +
      '" style="padding-left: ' +
      paddingLeft +
      'px">' +
      chevron +
      '<span class="fa ' +
      icon +
      ' ' +
      iconColor +
      '"></span>' +
      '<span class="tree-label">' +
      safeTitle +
      '</span>' +
      (item.parentIds && item.parentIds.length > 1
        ? '<span class="tree-shared-badge" title="Appears in ' +
        item.parentIds.length + ' collections">' +
        '<span class="fa fa-link"></span> shared</span>'
        : '') +
      count +
      '</div>'

    if (hasChildren) {
      html +=
        '<div class="tree-children" style="display: none;">' +
        children
          .map(function (c) {
            return renderTreeItem(c, hierarchyMap, depth + 1)
          })
          .join('') +
        '</div>'
    }

    return html
  }

  // Bind tree toggle events
  function bindTreeEvents() {
    $('.tree-item')
      .off('click')
      .on('click', function (e) {
        e.stopPropagation()
        var $children = $(this).next('.tree-children')
        var $chevron = $(this).find('.tree-chevron')

        if ($children.length > 0) {
          if ($children.is(':visible')) {
            $children.slideUp(CONSTANTS.ANIMATION_SPEED)
            $chevron.removeClass('fa-chevron-down').addClass('fa-chevron-right')
          } else {
            $children.slideDown(CONSTANTS.ANIMATION_SPEED)
            $chevron.removeClass('fa-chevron-right').addClass('fa-chevron-down')
          }
        }
      })
  }

  // ============================================================================
  // SETTINGS & NAVIGATION
  // ============================================================================

  // Initialize visibility cards
  function initVisibilityCards() {
    $('.visibility-card').off('click').on('click', function () {
      var visibility = $(this).data('visibility')
      $('.visibility-card').removeClass('active')
      $(this).addClass('active')
      $(this).find('input[type="radio"]').prop('checked', true)
      StepperState.settings.visibility = visibility
    })

    // Set default
    $('.visibility-card[data-visibility="open"]').addClass('active')
  }

  // Set default import name
  function setDefaultImportName() {
    var today = new Date()
    var dateStr =
      today.getMonth() + 1 + '/' + today.getDate() + '/' + today.getFullYear()
    var defaultName = 'CSV Import - ' + dateStr
    $('#bulkrax_importer_name').val(defaultName)
    StepperState.settings.name = defaultName
  }

  // Initialize admin set state with pre-selected value
  function initAdminSetState() {
    var $adminSetSelect = $('#importer_admin_set_id')
    if ($adminSetSelect.length) {
      var currentVal = $adminSetSelect.val()
      if (currentVal && currentVal.trim() !== '') {
        StepperState.settings.adminSetId = currentVal.trim()
        StepperState.settings.adminSetName = $adminSetSelect.find('option:selected').text().trim()
      }
    }
  }

  // Navigate to step
  function goToStep(stepNum) {
    StepperState.currentStep = stepNum
    updateStepperUI()

    // Scroll to top
    $('html, body').animate({ scrollTop: 0 }, CONSTANTS.SCROLL_SPEED)

    // Update review summary if going to step 3
    if (stepNum === 3) {
      updateReviewSummary()
    }
  }

  // Update stepper UI based on current step
  function updateStepperUI() {
    var step = StepperState.currentStep

    // Update step header
    $('.step-item').each(function () {
      var itemStep = parseInt($(this).data('step'))
      $(this).removeClass('active completed')

      if (itemStep === step) {
        $(this).addClass('active')
      } else if (itemStep < step) {
        $(this).addClass('completed')
      }
    })

    // Update step connectors
    $('.step-connector').each(function (index) {
      if (index < step - 1) {
        $(this).addClass('completed')
      } else {
        $(this).removeClass('completed')
      }
    })

    // Show/hide step content
    $('.step-content').hide()
    $('.step-content[data-step="' + step + '"]').show()

    // Update navigation buttons
    updateStepNavigation()
  }

  // Update step navigation button states
  function updateStepNavigation() {
    var step = StepperState.currentStep

    if (step === 1) {
      var data = StepperState.validationData
      var isValid = data && data.isValid
      var hasWarnings = data && data.hasWarnings
      var canProceed = StepperState.skipValidation ||
        (StepperState.validated &&
          isValid &&
          (!hasWarnings || StepperState.warningsAcked))

      $('.step-content[data-step="1"] .step-next-btn').prop('disabled', !canProceed)
    } else if (step === 2) {
      var $nameInput = $('input[name$="[name]"][name*="importer"]').first()
      var $adminSetSelect = $('select[name$="[admin_set_id]"][name*="importer"]').first()
      var name = ($nameInput.length ? $nameInput.val() : '').trim()
      var adminSetId = ($adminSetSelect.length ? $adminSetSelect.val() : '').trim()
      var canProceed = name.length > 0 && adminSetId.length > 0
      StepperState.settings.name = name || StepperState.settings.name
      StepperState.settings.adminSetId = adminSetId || StepperState.settings.adminSetId
      $('.step-content[data-step="2"] .step-next-btn').prop('disabled', !canProceed)
    }
  }

  // Update review summary
  function updateReviewSummary() {
    var data = StepperState.validationData
    var settings = StepperState.settings

    // Files
    var filesHtml = StepperState.uploadedFiles
      .map(function (f) {
        var type = f.fileType === 'csv' ? 'CSV' : 'ZIP'
        var fromZip = f.fromZip ? ' — detected in ZIP' : ''
        return (
          '<p>' + type + ': ' + f.name + ' (' + f.size + ')' + fromZip + '</p>'
        )
      })
      .join('')
    $('.review-files').html(filesHtml)

    // Records
    var totalItems =
      data.collections.length + data.works.length + data.fileSets.length
    var recordsHtml =
      '<p>' +
      totalItems +
      ' total — ' +
      data.collections.length +
      ' collections, ' +
      data.works.length +
      ' works, ' +
      data.fileSets.length +
      ' file sets</p>'
    $('.review-records').html(recordsHtml)

    // Settings - get admin set name from DOM first, then fallback to state
    var $currentAdminSet = $('#importer_admin_set_id')
    var adminSetName = 'Not selected'
    if ($currentAdminSet.length) {
      var selectedText = $currentAdminSet.find('option:selected').text().trim()
      var selectedValue = $currentAdminSet.val()
      if (selectedValue && selectedValue !== '' && selectedText !== 'Select an admin set...') {
        adminSetName = selectedText
      }
    }
    if (adminSetName === 'Not selected' && settings.adminSetName) {
      adminSetName = settings.adminSetName
    }
    var visibilityLabels = {
      open: 'Public',
      authenticated: 'Institution',
      restricted: 'Private'
    }
    var visibilityName = visibilityLabels[settings.visibility]

    var settingsHtml =
      '<p>Name: ' +
      settings.name +
      '</p>' +
      '<p>Admin Set: ' +
      adminSetName +
      '</p>' +
      '<p>Visibility: ' +
      visibilityName +
      '</p>'

    if (settings.rightsStatement) {
      settingsHtml += '<p>Rights: ' + settings.rightsStatement + '</p>'
    }
    if (settings.limit) {
      settingsHtml += '<p>Limit: first ' + settings.limit + ' records</p>'
    }

    $('.review-settings').html(settingsHtml)

    // Warnings
    if (data.hasWarnings) {
      var warningsHtml = '<ul class="small">'
      if (data.unrecognized.length > 0) {
        warningsHtml +=
          '<li>• ' +
          data.unrecognized.length +
          ' unrecognized column(s) will be ignored</li>'
      }
      if (data.missingFiles.length > 0) {
        warningsHtml +=
          '<li>• ' + data.missingFiles.length + ' file(s) missing from ZIP</li>'
      }
      warningsHtml += '</ul>'
      $('.review-warnings-list').html(warningsHtml)
      $('.review-warnings').show()
    }

    // Large import warning
    $('.total-items-count').text(totalItems)
    if (totalItems > CONSTANTS.IMPORT_SIZE_MODERATE) {
      $('.large-import-warning').show()
    } else {
      $('.large-import-warning').hide()
    }
  }

  // ============================================================================
  // FORM SUBMISSION & SUCCESS STATE
  // ============================================================================

  // Handle import submission
  function handleImportSubmit() {
    var $btn = $('#start-import-btn')
    var $form = $('#bulk-import-stepper-form')
    $btn
      .prop('disabled', true)
      .html('<span class="fa fa-spinner fa-spin"></span> Starting...')

    // Submit the form so the request hits create_v2 and creates the importer / enqueues job
    $form[0].submit()
  }

  // Show success state
  function showSuccessState() {
    $('.stepper-content-wrapper').hide()
    $('.stepper-header').hide()
    $('.import-success-state').show()
  }

  // Look up mock validation data from cached demo scenarios JSON
  function getMockValidationData() {
    var scenario = StepperState.demoScenario || 'warning_combined'
    var data = StepperState.demoScenariosData
    if (!data || !data.scenarios || !data.scenarios[scenario]) return null
    return data.scenarios[scenario].response
  }

  // ============================================================================
  // UTILITY FUNCTIONS
  // ============================================================================

  function showNotification(message, type) {
    type = type || 'info' // 'error', 'warning', 'info'

    var icons = {
      error: 'fa-times-circle',
      warning: 'fa-exclamation-triangle',
      info: 'fa-info-circle'
    }

    // Escape the message to prevent XSS
    var safeMessage = escapeHtml(message)

    var $notification = $(
      '<div class="upload-notification notification-' + type + '">' +
      '<span class="fa ' + icons[type] + ' upload-notification-icon"></span>' +
      '<div class="upload-notification-content">' + safeMessage + '</div>' +
      '<span class="fa fa-times upload-notification-close"></span>' +
      '</div>'
    )

    $('#upload-notifications').append($notification)

    // Click to dismiss
    $notification.find('.upload-notification-close').on('click', function () {
      $notification.fadeOut(CONSTANTS.NOTIFICATION_FADE_SPEED, function () {
        $(this).remove()
      })
    })
  }

  // Initialize on document ready and turbolinks load
  $(document).on('ready turbolinks:load', initBulkImportStepper)
})(jQuery, window.BulkraxUtils || {})
