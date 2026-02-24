// Bulk Import Stepper - Multi-step wizard for CSV/ZIP imports
// Handles file uploads, validation, settings, and review steps
//
// DEPENDENCIES:
// - jQuery (global)
// - BulkraxUtils (from bulkrax_utils.js - must load first)
//
// TABLE OF CONTENTS:
// - Utility Functions
// - Constants & Configuration
// - State Management
// - Initialization
// - Event Binding
// - File Validation & Utilities
// - File Upload Handlers
// - Demo Scenarios
// - Upload State Management
// - Validation
// - Validation Results Rendering
// - Import Summary & Hierarchy
// - Settings & Navigation
// - Form Submission & Success State
// - Notification Functions

; (function ($, Utils) {
  'use strict'

  // Import utilities from BulkraxUtils
  var escapeHtml = Utils.escapeHtml
  var formatFileSize = Utils.formatFileSize
  var normalizeBoolean = Utils.normalizeBoolean

  // ============================================================================
  // UTILITY FUNCTIONS
  // ============================================================================

  // Delays function execution until after 'wait' milliseconds have passed
  // since the last time it was invoked
  function debounce(func, wait) {
    var timeout
    return function debounced() {
      var context = this
      var args = arguments
      clearTimeout(timeout)
      timeout = setTimeout(function () {
        func.apply(context, args)
      }, wait)
    }
  }

  // ============================================================================
  // CONSTANTS & CONFIGURATION
  // ============================================================================

  var CONSTANTS = {
    // File upload limits
    MAX_FILES: 2,
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
    DEBOUNCE_DELAY: 300,

    // AJAX timeouts (in milliseconds)
    AJAX_TIMEOUT_SHORT: 10000, // 10 seconds for simple requests
    AJAX_TIMEOUT_LONG: 120000, // 2 minutes for validation

    // Chunked upload settings (matches Hyrax v1 uploader)
    CHUNK_SIZE: 10000000, // 10 MB per chunk
    UPLOAD_URL: '/uploads/',

    // Hierarchy rendering limits
    MAX_TREE_DEPTH: 50, // Prevent stack overflow on deeply nested hierarchies

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
    uploadMode: 'upload', // 'upload' or 'file_path'
    validated: false,
    validationData: null,
    warningsAcked: false,
    skipValidation: false, // Flag to skip validation step
    isAddingFiles: false, // Flag to track if we're adding files vs replacing
    demoScenario: null, // Track which demo scenario is loaded
    demoScenariosData: null, // Cached demo scenarios JSON from server
    uploadsInProgress: 0,
    adminSetId: '',
    adminSetName: '',
    settings: {
      name: '',
      visibility: 'open',
      rightsStatement: '',
      limit: ''
    }
  }

  // Guard flag to prevent rebinding events on every page load (Turbolinks)
  var eventsInitialized = false

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
    updateDownloadTemplateLink()
    updateStepperUI()
    initVisibilityCards()
    setDefaultImportName()
  }

  // ============================================================================
  // EVENT BINDING
  // ============================================================================

  // Bind all event handlers
  function bindEvents() {
    // Only bind events once, even if initBulkImportStepper runs multiple times
    if (eventsInitialized) {
      return // Events already bound, skip rebinding
    }

    // File upload - main dropzone
    $('.upload-dropzone').on('click', function (e) {
      if (e.target.id === 'file-input') return

      StepperState.isAddingFiles = false
      $('#file-input').trigger('click')
    })

    // Delegated event handlers for dynamic content
    // These only need to be bound once since they listen on stable parent containers
    bindDelegatedEvents()

    // File upload - add another dropzone
    $('.upload-dropzone-small').on('click', function () {
      StepperState.isAddingFiles = true
      $('#file-input').trigger('click')
    })

    $('#file-input').on('change', function () {
      handleFileSelect(StepperState.isAddingFiles)
      StepperState.isAddingFiles = false // Reset flag after handling
    })

    // Drag and drop - main dropzone
    $('.upload-dropzone').on('dragover', function (e) {
      e.preventDefault()
      $(this).addClass('dragover')
    })

    $('.upload-dropzone').on('dragleave', function (e) {
      e.preventDefault()
      $(this).removeClass('dragover')
    })

    $('.upload-dropzone').on('drop', function (e) {
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

        // Show warning if more than MAX_FILES were dropped
        if (droppedFiles.length > CONSTANTS.MAX_FILES) {
          showNotification(
            'Only the first ' + CONSTANTS.MAX_FILES + ' files have been uploaded. You can upload up to ' + CONSTANTS.MAX_FILES + ' files (1 CSV and 1 ZIP).'
          )
        }
      }
    })

    // Drag and drop - small "add another" dropzone
    $('.upload-dropzone-small').on('dragover', function (e) {
      e.preventDefault()
      $(this).addClass('dragover')
    })

    $('.upload-dropzone-small').on('dragleave', function (e) {
      e.preventDefault()
      $(this).removeClass('dragover')
    })

    $('.upload-dropzone-small').on('drop', function (e) {
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

    // Upload mode tabs
    $('.upload-mode-tab').on('click', function () {
      var mode = $(this).data('upload-mode')
      switchUploadMode(mode)
    })

    // File path input
    $('#import-file-path').on('input', debounce(function () {
      updateValidateButtonState()
    }, CONSTANTS.DEBOUNCE_DELAY))

    // Demo scenarios (for testing)
    $('.step-circle').on('dblclick', function () {
      var $panel = $('.demo-scenarios')
      $panel.toggle()
      if ($panel.is(':visible')) {
        // Prefetch scenarios data
        loadDemoScenariosData().catch(function () {
          // Error already handled in loadDemoScenariosData
        })
      }
    })

    $('.scenario-btn').on('click', function () {
      var scenario = $(this).data('scenario')
      loadDemoScenario(scenario)
      $('.demo-scenarios').hide()
    })

    // Start over
    $('#start-over-btn').on('click', function () {
      resetUploadState()
    })

    // Start over
    $('#upload-different-btn').on('click', function (e) {
      e.preventDefault()
      resetUploadState()
    })

    // Validate button
    $('#validate-btn').on('click', function () {
      validateFiles()
    })

    // Warnings acknowledgment
    $('#warnings-acked').on('change', function () {
      StepperState.warningsAcked = $(this).is(':checked')
      updateStepNavigation()
    })

    // Step navigation - next step
    $('.step-next-btn').on('click', function () {
      var nextStep = parseInt($(this).data('next-step'))
      goToStep(nextStep)
    })

    // Step navigation - previous step
    $('.step-prev-btn').on('click', function () {
      var prevStep = parseInt($(this).data('prev-step'))
      goToStep(prevStep)
    })

    // Form submission
    $('#bulk-import-stepper-form').on('submit', function (e) {
      e.preventDefault()
      handleImportSubmit()
    })

    // Start another import
    $('#start-another-import').on('click', function () {
      location.reload()
    })

    // Settings form changes
    $('#bulkrax_importer_name').on('input', debounce(function () {
      StepperState.settings.name = $(this).val()
      updateStepNavigation()
    }, CONSTANTS.DEBOUNCE_DELAY))

    // Admin set selection change
    $('#importer-admin-set').on('change', function () {
      StepperState.adminSetId = $(this).val()
      StepperState.settings.adminSetName = $(this).find('option:selected').text()
      updateStepNavigation()
      updateDownloadTemplateLink()
      // Update validate button state since admin set is required for validation
      if (StepperState.uploadMode === 'file_path' || StepperState.uploadedFiles.length > 0) {
        updateValidateButtonState()
      }
    })

    // Rights statement selection change
    $('select[name="importer[parser_fields][rights_statement]"]').on('change', function () {
      StepperState.settings.rightsStatement = $(this).find('option:selected').text().trim()
      // Clear if "None" was selected
      if (!$(this).val()) {
        StepperState.settings.rightsStatement = ''
      }
      updateStepNavigation()
    })

    $('#bulkrax_importer_limit').on('input', debounce(function () {
      StepperState.settings.limit = $(this).val()
    }, CONSTANTS.DEBOUNCE_DELAY))

    // Remove file button (delegated to parent since rows are dynamic)
    $('.uploaded-files-container').on('click', '.file-remove-btn', function () {
      var $row = $(this).closest('.file-row')
      var fileId = $row.data('file-id')

      var fileEntry = StepperState.uploadedFiles.find(function (f) { return f.id === fileId })
      if (fileEntry) {
        if (fileEntry.uploadXhr) {
          fileEntry.uploadXhr.abort()
          StepperState.uploadsInProgress--
        }
        if (fileEntry.uploadId) {
          $.ajax({ url: CONSTANTS.UPLOAD_URL + fileEntry.uploadId, method: 'DELETE', timeout: CONSTANTS.AJAX_TIMEOUT_SHORT })
        }
      }

      // Remove from uploadedFiles array
      StepperState.uploadedFiles = StepperState.uploadedFiles.filter(
        function (file) { return file.id !== fileId }
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
    $('#skip-validation-checkbox').on('change', function () {
      StepperState.skipValidation = $(this).is(':checked')
      updateStepNavigation()
    })

    // Mark events as initialized to prevent rebinding on subsequent page loads
    eventsInitialized = true
  }

  // Bind delegated event handlers for dynamically rendered content
  // These handlers are attached to stable parent containers and use event delegation
  // to handle clicks on child elements. This is more efficient than rebinding handlers
  // every time content is re-rendered.
  function bindDelegatedEvents() {
    // Accordion toggle events - delegated to validation results container
    $('.validation-results').on('click.accordion', '.accordion-header', function () {
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

    // Tree toggle events - delegated to import summary container
    $('.import-summary').on('click.tree', '.tree-item', function (e) {
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
  // FILE VALIDATION & UTILITIES
  // ============================================================================

  // Check if DataTransfer constructor is available
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
      var parts = [
        '<div class="alert alert-danger alert-dismissible" role="alert">',
        '<button type="button" class="close" data-dismiss="alert" aria-label="Close">',
        '<span aria-hidden="true">&times;</span>',
        '</button>',
        '<strong><span class="fa fa-exclamation-circle"></span> File Upload Error</strong>',
        '<ul class="mb-0 mt-2">'
      ]

      messages.forEach(function (msg) {
        // Escape the message but allow intentional <br> tags for newlines
        var escapedMsg = escapeHtml(msg).replace(/\n/g, '<br>')
        parts.push('<li>' + escapedMsg + '</li>')
      })

      parts.push('</ul>', '</div>')
      errorContainer.html(parts.join('')).show()
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

  // Get tenant/account max file size (bytes) from the page, same source as v1 uploader
  function getMaxFileSize() {
    var val = $('.bulk-import-stepper-container').data('max-file-size')
    if (val == null || val === '') return null
    return parseInt(val, 10) || null
  }

  // Handle file selection
  function handleFileSelect(isAddingMore) {
    var files = $('#file-input')[0].files
    if (files.length === 0) return

    var maxFileSizeBytes = getMaxFileSize()

    // If not adding more, reset the uploaded files array
    if (!isAddingMore) {
      StepperState.uploadedFiles = []
    }

    // Count existing file types
    var existingCounts = StepperState.uploadedFiles.reduce(function (counts, f) {
      if (f.fileType === 'csv' && !f.fromZip) counts.csv++
      if (f.fileType === 'zip') counts.zip++
      return counts
    }, { csv: 0, zip: 0 })
    var existingCsvCount = existingCounts.csv
    var existingZipCount = existingCounts.zip

    var addedFiles = []
    var rejectedFiles = []
    var newEntries = []

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

      // Respect tenant/account file size limit (same as v1 and Hyrax uploader)
      if (maxFileSizeBytes != null && file.size > maxFileSizeBytes) {
        rejectedFiles.push({
          name: fileName,
          reason: 'file_too_large',
          size: file.size,
          limit: maxFileSizeBytes
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

      // Add the file with upload tracking properties
      var fileEntry = {
        id: Date.now() + i,
        name: fileName,
        size: fileSize,
        fileType: fileType,
        fromZip: false,
        file: file,
        uploadId: null,
        uploadProgress: 0,
        uploadComplete: false,
        uploadXhr: null
      }
      StepperState.uploadedFiles.push(fileEntry)
      newEntries.push(fileEntry)

      addedFiles.push(fileName)

      // Update counts
      if (fileType === 'csv') existingCsvCount++
      if (fileType === 'zip') existingZipCount++
    }

    // Show appropriate warnings
    if (rejectedFiles.length > 0) {
      var messages = []

      var categorized = rejectedFiles.reduce(function (acc, f) {
        if (f.reason === 'invalid_type') acc.invalidTypes.push(f)
        else if (f.reason === 'file_too_large') acc.fileTooLarge.push(f)
        else if (f.reason === 'duplicate CSV') acc.duplicateCsv.push(f)
        else if (f.reason === 'duplicate ZIP') acc.duplicateZip.push(f)
        else if (f.reason === 'duplicate') acc.duplicates.push(f)
        return acc
      }, { invalidTypes: [], fileTooLarge: [], duplicateCsv: [], duplicateZip: [], duplicates: [] })

      // Handle invalid file types FIRST
      if (categorized.invalidTypes.length > 0) {
        messages.push(
          'Invalid file format. Only .csv and .zip files are allowed.\n' +
          'The following files were rejected:\n• ' +
          categorized.invalidTypes.map(function (f) {
            return f.name + ' (' + (f.extension || 'no extension') + ')'
          }).join('\n• ')
        )
      }

      if (categorized.fileTooLarge.length > 0) {
        var limitMb = categorized.fileTooLarge[0].limit / (1024 * 1024)
        messages.push(
          'File size exceeds the maximum allowed (' + Math.round(limitMb) + ' MB per file).\n' +
          'The following files were rejected:\n• ' +
          categorized.fileTooLarge.map(function (f) {
            return f.name + ' (' + formatFileSize(f.size) + ')'
          }).join('\n• ')
        )
      }

      if (categorized.duplicateCsv.length > 0) {
        messages.push(
          'Only 1 CSV file allowed. The following files were not added:\n• ' +
          categorized.duplicateCsv
            .map(function (f) {
              return f.name
            })
            .join('\n• ')
        )
      }
      if (categorized.duplicateZip.length > 0) {
        messages.push(
          'Only 1 ZIP file allowed. The following files were not added:\n• ' +
          categorized.duplicateZip
            .map(function (f) {
              return f.name
            })
            .join('\n• ')
        )
      }
      if (categorized.duplicates.length > 0) {
        messages.push(
          'The following files were already uploaded:\n• ' +
          categorized.duplicates
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

    // Start chunked uploads for newly added files
    newEntries.forEach(function (entry) {
      if (entry.file) {
        uploadFileChunked(entry)
      }
    })
  }

  // ============================================================================
  // DEMO SCENARIOS
  // ============================================================================

  var demoScenariosRequest = null

  // Fetch and cache demo scenarios JSON from server
  function loadDemoScenariosData() {
    // Return cached data as resolved promise
    if (StepperState.demoScenariosData) {
      return Promise.resolve(StepperState.demoScenariosData)
    }

    // Return existing promise if request is already in-flight
    if (demoScenariosRequest) {
      return demoScenariosRequest
    }

    demoScenariosRequest = $.ajax({
      url: CONSTANTS.ENDPOINTS.DEMO_SCENARIOS,
      method: 'GET',
      dataType: 'json',
      timeout: CONSTANTS.AJAX_TIMEOUT_SHORT
    })
      .then(function (data) {
        StepperState.demoScenariosData = data
        demoScenariosRequest = null // Clear in-flight tracker
        return data
      })
      .catch(function (xhr) {
        demoScenariosRequest = null // Clear in-flight tracker on error

        var status = xhr.statusText || 'error'
        var errorMsg = 'Failed to load demo scenarios'

        if (status === 'timeout') {
          errorMsg = 'Request timed out while loading demo scenarios'
        } else if (xhr.status === 0) {
          errorMsg = 'Network error - please check your connection'
        } else if (xhr.status >= 500) {
          errorMsg = 'Server error while loading demo scenarios'
        }

        console.warn(errorMsg, {
          status: status,
          error: xhr.statusText,
          statusCode: xhr.status
        })
        showNotification(errorMsg, 'error')

        // Re-throw to allow caller to handle
        throw new Error(errorMsg)
      })

    return demoScenariosRequest
  }

  // Load demo scenario from cached JSON
  function loadDemoScenario(scenario) {
    resetUploadState()

    loadDemoScenariosData()
      .then(function (data) {
        if (!data || !data.scenarios || !data.scenarios[scenario]) {
          console.warn('Demo scenario not found:', scenario)
          return
        }

        StepperState.uploadedFiles = data.scenarios[scenario].files
        StepperState.demoScenario = scenario
        updateUploadState()
        renderUploadedFiles()
      })
      .catch(function (error) {
        // Error already handled and displayed in loadDemoScenariosData
        console.error('Failed to load demo scenario:', error)
      })
  }

  // ============================================================================
  // CHUNKED FILE UPLOAD (to Hyrax /uploads/ endpoint)
  // ============================================================================

  function uploadFileChunked(fileEntry) {
    var file = fileEntry.file
    if (!file) return

    StepperState.uploadsInProgress++
    fileEntry.uploadProgress = 0
    fileEntry.uploadComplete = false
    fileEntry.uploadId = null

    updateValidateButtonState()
    renderUploadedFiles()

    var chunkSize = CONSTANTS.CHUNK_SIZE
    var totalSize = file.size
    var offset = 0

    function sendNextChunk() {
      if (offset >= totalSize) {
        fileEntry.uploadComplete = true
        fileEntry.uploadProgress = 100
        StepperState.uploadsInProgress--
        updateValidateButtonState()
        renderUploadedFiles()
        return Promise.resolve()
      }

      var end = Math.min(offset + chunkSize, totalSize)
      var isFirstChunk = (offset === 0)
      var chunk = file.slice(offset, end)

      var formData = new FormData()
      formData.append('files[]', chunk, file.name)

      var headers = {}
      if (!isFirstChunk) {
        formData.append('id', fileEntry.uploadId)
        headers['Content-Range'] = 'bytes ' + offset + '-' + (end - 1) + '/' + totalSize
      }

      var currentOffset = offset

      return new Promise(function (resolve, reject) {
        var ajaxOptions = {
          url: CONSTANTS.UPLOAD_URL,
          method: 'POST',
          data: formData,
          processData: false,
          contentType: false,
          dataType: 'json',
          timeout: 0,
          xhr: function () {
            var xhr = new XMLHttpRequest()
            xhr.upload.addEventListener('progress', function (e) {
              if (e.lengthComputable) {
                var chunkLoaded = currentOffset + e.loaded
                var percent = Math.round((chunkLoaded / totalSize) * 100)
                fileEntry.uploadProgress = Math.min(percent, 99)
                renderUploadProgress(fileEntry)
              }
            })
            return xhr
          }
        }

        if (Object.keys(headers).length > 0) {
          ajaxOptions.headers = headers
        }

        var jqXhr = $.ajax(ajaxOptions)
        fileEntry.uploadXhr = jqXhr
        jqXhr
          .then(function (result) {
            if (isFirstChunk && result.files && result.files[0]) {
              fileEntry.uploadId = result.files[0].id
            }
            offset = end
            fileEntry.uploadXhr = null
            resolve()
          })
          .catch(function (xhr) {
            fileEntry.uploadXhr = null
            reject(new Error(xhr.statusText || 'Upload failed'))
          })
      }).then(sendNextChunk)
    }

    sendNextChunk().catch(function (error) {
      StepperState.uploadsInProgress--
      StepperState.uploadedFiles = StepperState.uploadedFiles.filter(function (f) {
        return f !== fileEntry
      })
      updateUploadState()
      updateValidateButtonState()
      renderUploadedFiles()
      if (error.message !== 'abort') {
        showNotification('Upload failed for ' + file.name + ': ' + (error.message || 'Unknown error'), 'error')
      }
    })
  }

  function renderUploadProgress(fileEntry) {
    var $row = $('.file-row[data-file-id="' + fileEntry.id + '"]')
    if ($row.length) {
      var pct = fileEntry.uploadProgress || 0
      $row.find('.upload-progress-bar').css('width', pct + '%')
      $row.find('.upload-progress-label').text('Uploading… ' + pct + '%')
    }
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

    var fileFlags = files.reduce(function (flags, f) {
      if (f.fileType === 'csv' && !f.fromZip) flags.hasStandaloneCsv = true
      if (f.fileType === 'zip') flags.hasZip = true
      if (f.fileType === 'csv' && f.fromZip) flags.hasCsvInZip = true
      return flags
    }, { hasStandaloneCsv: false, hasZip: false, hasCsvInZip: false })

    var hasStandaloneCsv = fileFlags.hasStandaloneCsv
    var hasZip = fileFlags.hasZip
    var hasCsvInZip = fileFlags.hasCsvInZip

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

  // Switch between upload and file path modes
  function switchUploadMode(mode) {
    if (mode === StepperState.uploadMode) return

    StepperState.uploadMode = mode

    // Toggle active tab
    $('.upload-mode-tab').removeClass('active')
    $('.upload-mode-tab[data-upload-mode="' + mode + '"]').addClass('active')

    if (mode === 'file_path') {
      // Hide upload-related elements, show file path panel
      $('.upload-zone-empty').hide()
      $('.uploaded-files-container').hide()
      $('.add-another-dropzone').hide()
      $('.file-path-panel').show()
      $('.start-over-link').hide()
    } else {
      // Hide file path panel, restore upload state
      $('.file-path-panel').hide()
      renderUploadedFiles()
    }

    updateValidateButtonState()
  }

  // Update validate button enabled state based on current upload mode
  function updateValidateButtonState() {
    var $adminSetSelect = $('#importer-admin-set')
    var adminSetValue = $adminSetSelect.val() || StepperState.adminSetId
    var hasAdminSet = adminSetValue && adminSetValue.length > 0

    var canValidate = false

    if (StepperState.uploadMode === 'file_path') {
      var filePath = $('#import-file-path').val() || ''
      canValidate = filePath.trim().length > 0 && hasAdminSet
    } else {
      var fileCheck = StepperState.uploadedFiles.reduce(function (check, f) {
        if (f.fileType === 'csv') check.hasCsv = true
        if (f.fileType === 'zip') check.hasZip = true
        return check
      }, { hasCsv: false, hasZip: false })
      canValidate = (fileCheck.hasCsv || fileCheck.hasZip) && hasAdminSet && !StepperState.validated && StepperState.uploadsInProgress === 0
    }

    $('#validate-btn').prop('disabled', !canValidate)
    $('#skip-validation-checkbox').prop('disabled', !canValidate && !StepperState.skipValidation)
  }

  // Render uploaded files
  function renderUploadedFiles() {
    // Ensure admin set state is captured (handles timing issues)
    // Always refresh from DOM to ensure we have the current value
    var $adminSetSelect = $('#importer-admin-set')
    if ($adminSetSelect.length && $adminSetSelect.val()) {
      StepperState.adminSetId = $adminSetSelect.val()
      StepperState.adminSetName = $adminSetSelect.find('option:selected').text()
    }

    var state = StepperState.uploadState
    var files = StepperState.uploadedFiles

    // Don't manipulate upload DOM elements when in file path mode
    if (StepperState.uploadMode === 'file_path') return

    if (state === CONSTANTS.UPLOAD_STATES.EMPTY) {
      $('.upload-zone-empty').show()
      $('.uploaded-files-container').hide()
      $('.add-another-dropzone').hide()
      $('.start-over-link').hide()
      updateValidateButtonState()
      return
    }

    $('.upload-zone-empty').hide()
    $('.uploaded-files-container').show()

    var $list = $('.uploaded-files-list')
    $list.empty()

    // Render all uploaded files
    var fileRows = files.map(function (file) {
      return renderFileRow(file)
    })
    $list.append(fileRows.join(''))

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
    } else {
      $('.add-another-dropzone').hide()
      $('.start-over-link').show()
    }

    updateValidateButtonState()
  }

  // Render a single file row
  function renderFileRow(file) {
    var type = file.fileType
    var name = file.name
    var subtitle = file.subtitle || file.size
    // Show progress until server has accepted the file (uploadId); demo entries may have no .file
    var isUploading = file.file && !file.uploadId
    var verified = !isUploading

    var icon = type === 'csv' ? 'fa-file-text' : 'fa-file-archive-o'
    var iconBg = type === 'csv' ? 'file-icon-csv' : 'file-icon-zip'

    var progress = file.uploadProgress || 0
    var progressBlock = ''
    if (isUploading) {
      progressBlock =
        '<div class="upload-progress-block">' +
        '<div class="upload-progress-label">Uploading… ' + progress + '%</div>' +
        '<div class="upload-progress-bar-container">' +
        '<div class="upload-progress-bar" style="width:' + progress + '%;"></div>' +
        '</div>' +
        '</div>'
    }

    var statusHtml = verified
      ? '<span class="fa fa-check-circle file-verified"></span>'
      : ''

    var safeName = escapeHtml(name)
    var safeSubtitle = escapeHtml(subtitle)

    return (
      '<div class="file-row" data-file-id="' + file.id + '">' +
      '<div class="file-row-main">' +
      '<div class="file-info">' +
      '<div class="file-icon ' + iconBg + '"><span class="fa ' + icon + '"></span></div>' +
      '<div class="file-details">' +
      '<div class="file-name">' + safeName + '</div>' +
      '<div class="file-subtitle">' + safeSubtitle + '</div>' +
      '</div>' +
      '</div>' +
      '<div class="file-actions">' +
      statusHtml +
      '<button type="button" class="file-remove-btn" aria-label="Remove file">' +
      '<span class="fa fa-times"></span>' +
      '</button>' +
      '</div>' +
      '</div>' +
      progressBlock +
      '</div>'
    )
  }

  // Reset upload state
  function resetUploadState() {
    // Abort in-progress uploads and delete server-side files
    StepperState.uploadedFiles.forEach(function (f) {
      if (f.uploadXhr) f.uploadXhr.abort()
      if (f.uploadId) {
        $.ajax({ url: CONSTANTS.UPLOAD_URL + f.uploadId, method: 'DELETE', timeout: CONSTANTS.AJAX_TIMEOUT_SHORT })
      }
    })
    StepperState.uploadsInProgress = 0

    StepperState.uploadedFiles = []
    StepperState.uploadState = CONSTANTS.UPLOAD_STATES.EMPTY
    StepperState.validated = false
    StepperState.validationData = null
    StepperState.warningsAcked = false
    StepperState.skipValidation = false
    StepperState.demoScenario = null
    $('#file-input').val('')
    $('#import-file-path').val('')
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

  // Perform validation API call with uploaded file IDs
  function performValidation(data) {
    return $.ajax({
      url: CONSTANTS.ENDPOINTS.VALIDATE,
      method: 'POST',
      data: data,
      timeout: CONSTANTS.AJAX_TIMEOUT_LONG
    })
  }

  function performFilePathValidation(filePath) {
    return $.ajax({
      url: CONSTANTS.ENDPOINTS.VALIDATE,
      method: 'POST',
      data: {
        importer: {
          parser_fields: {
            import_file_path: filePath
          },
          admin_set_id: StepperState.adminSetId
        }
      },
      timeout: CONSTANTS.AJAX_TIMEOUT_LONG
    })
  }

  // Simulate validation for demo scenarios
  function performMockValidation() {
    return new Promise(function (resolve, reject) {
      setTimeout(function () {
        var mockData = getMockValidationData()
        if (!mockData) {
          reject(new Error('Demo data not loaded. Try selecting a scenario again.'))
          return
        }
        resolve(mockData)
      }, CONSTANTS.VALIDATION_DELAY)
    })
  }

  // Update UI after successful validation
  function handleValidationSuccess(data, $btn) {
    var normalized = normalizeValidationData(data)
    StepperState.validated = true
    StepperState.validationData = normalized

    try {
      renderValidationResults(normalized)
      $btn.html('<span class="fa fa-check-circle"></span> Validated')
      $('.start-over-link').show()
      updateStepNavigation()
    } catch (e) {
      console.error('Validation results render issue:', e)
      throw new Error('Validation completed but results could not be displayed. Please try again.')
    }
  }

  // Update UI after validation error
  function handleValidationError(error, $btn) {
    var xhr = error
    var status = xhr.statusText || 'error'
    var errorMsg = 'Validation failed. Please try again.'

    // Handle specific error cases
    if (status === 'timeout') {
      errorMsg = 'Validation timed out. Your files may be too large. Please try with smaller files or contact support.'
    } else if (xhr.status === 0) {
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
      error: xhr.statusText,
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

  // Validate files (AJAX call to backend)
  function validateFiles() {
    var $btn = $('#validate-btn')
    $btn
      .prop('disabled', true)
      .html('<span class="fa fa-spinner fa-spin"></span> Validating...')

    // Check if we're in demo mode (no real uploaded files on server)
    var hasRealFiles = StepperState.uploadedFiles.some(function (f) { return f.uploadId })
    var filePathValue = $('#import-file-path').val().trim()
    var hasFilePath = filePathValue.length > 0
    var useMockData = !hasRealFiles && !hasFilePath

    // Send uploaded file IDs instead of raw file bytes
    var validationData
    if (!useMockData && !hasFilePath) {
      validationData = {
        uploaded_files: StepperState.uploadedFiles
          .filter(function (f) { return f.uploadId })
          .map(function (f) { return f.uploadId }),
        importer: {
          admin_set_id: StepperState.adminSetId
        }
      }
    }

    // Choose validation method based on mode
    var validationPromise
    if (hasFilePath) {
      validationPromise = performFilePathValidation(filePathValue)
    } else if (useMockData) {
      validationPromise = performMockValidation()
    } else {
      validationPromise = performValidation(validationData)
    }

    // Handle validation result
    validationPromise
      .then(function (data) {
        handleValidationSuccess(data, $btn)
      })
      .catch(function (error) {
        handleValidationError(error, $btn)
      })
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

    allItems.forEach(function (item) {
      if (item.childrenIds && item.childrenIds.length > 0) {
        item.childrenIds.forEach(function (childId) {
          var child = itemMap[childId]
          if (child) {
            if (child.parentIds.indexOf(item.id) === -1) {
              child.parentIds.push(item.id)
            }
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
    var groupedByModel = groupItemsByModel(items)
    var parts = []

    Object.keys(groupedByModel).forEach(function (modelName) {
      parts.push('<div class="missing-field-group">')
      parts.push('<strong class="missing-field-model">' + modelName + '</strong>')
      parts.push('<ul>')

      // Map fields to list items, then join once
      var fieldItems = groupedByModel[modelName].map(function (field) {
        return '<li>• ' + field + '</li>'
      })
      parts.push(fieldItems.join(''))

      parts.push('</ul>')
      parts.push('</div>')
    })

    return parts.join('')
  }

  // Render default issue items (unrecognized fields, file references, etc.)
  function renderDefaultIssueItems(items) {
    var listItems = items.map(function (item) {
      var msg = item.message ? ' — ' + item.message : ''
      return '<li>• ' + item.field + msg + '</li>'
    })

    return '<ul>' + listItems.join('') + '</ul>'
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
        var issueContent = ''

        if (issue.description) {
          issueContent += '<p>' + issue.description + '</p>'
        }

        if (issue.summary) {
          issueContent += '<p>' + issue.summary + '</p>'
        }

        if (issue.items && issue.items.length > 0) {
          issueContent += renderIssueItems(issue)
        }

        if (issue.details) {
          issueContent += '<p class="small">' + issue.details + '</p>'
        }

        $wrapper.append(
          createAccordion(
            issue.title,
            issue.icon,
            issue.severity,
            issue.count,
            issue.defaultOpen,
            issueContent
          )
        )
      })
    }

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

  // Note: Accordion toggle events are handled via event delegation in bindDelegatedEvents()

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
    var visited = new Set()
    var hierarchyContent =
      '<div class="hierarchy-tree">' +
      topLevelCollections
        .map(function (c) {
          return renderTreeItem(c, hierarchyMap, 0, visited)
        })
        .join('') +
      orphanWorks
        .map(function (w) {
          return renderTreeItem(w, hierarchyMap, 0, visited)
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

  }

  // Render tree item recursively using pre-computed hierarchyMap
  // Guarded with depth limit and circular reference detection
  function renderTreeItem(item, hierarchyMap, depth, visited) {
    depth = depth || 0

    // Limit tree depth to prevent stack overflow
    if (depth >= CONSTANTS.MAX_TREE_DEPTH) {
      console.warn('Max tree depth reached for item:', item.id)
      return '<div class="tree-item tree-truncated" style="padding-left: ' + (depth * 20) + 'px">' +
        '<span class="fa fa-ellipsis-h text-muted"></span>' +
        '<span class="tree-label text-muted"><em>Hierarchy too deep (max ' + CONSTANTS.MAX_TREE_DEPTH + ' levels)</em></span>' +
        '</div>'
    }

    // Detect circular references
    if (visited.has(item.id)) {
      console.error('Circular reference detected for item:', item.id)
      return '<div class="tree-item tree-error" style="padding-left: ' + (depth * 20) + 'px">' +
        '<span class="fa fa-exclamation-triangle text-danger"></span>' +
        '<span class="tree-label text-danger"><em>Circular reference detected</em></span>' +
        '</div>'
    }

    visited.add(item.id)

    var children = hierarchyMap[item.id] || []
    var hasChildren = children.length > 0
    var icon = item.type === 'collection' ? 'fa-folder' : 'fa-file-o'
    var iconColor = item.type === 'collection' ? 'text-primary' : 'text-muted'
    // Hidden chevron still takes up space (via fixed width in CSS) to prevent icon shifting
    var chevronClass = hasChildren ? 'tree-chevron' : 'tree-chevron tree-chevron-hidden'
    var chevron = '<span class="fa fa-chevron-right ' + chevronClass + '"></span>'
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
            return renderTreeItem(c, hierarchyMap, depth + 1, visited)
          })
          .join('') +
        '</div>'
    }

    return html
  }

  // Note: Tree toggle events are handled via event delegation in bindDelegatedEvents()

  // ============================================================================
  // SETTINGS & NAVIGATION
  // ============================================================================

  // Initialize visibility cards
  function initVisibilityCards() {
    $('.visibility-card').on('click', function () {
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
    var $adminSetSelect = $('#importer-admin-set')
    if ($adminSetSelect.length) {
      var currentVal = $adminSetSelect.val()
      if (currentVal && currentVal.trim() !== '') {
        StepperState.adminSetId = currentVal.trim()
        StepperState.adminSetName = $adminSetSelect.find('option:selected').text().trim()
      }
    }
  }

  function updateDownloadTemplateLink() {
    var $link = $('#download-csv-template-link')
    if (!$link.length) return
    var baseUrl = $link.data('sample-csv-url') || $link.attr('href')
    var adminSetId = $('#importer-admin-set').val()
    var href = baseUrl
    if (adminSetId && adminSetId.trim() !== '') {
      var sep = baseUrl.indexOf('?') >= 0 ? '&' : '?'
      href = baseUrl + sep + 'admin_set_id=' + encodeURIComponent(adminSetId.trim())
    }
    $link.attr('href', href)
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

  // Cached DOM selectors for updateStepNavigation
  var cachedSelectors = {
    nameInput: null,
    adminSetSelect: null,
    initialized: false
  }

  function initCachedSelectors() {
    if (!cachedSelectors.initialized) {
      cachedSelectors.nameInput = $('input[name$="[name]"][name*="importer"]').first()
      cachedSelectors.adminSetSelect = $('#importer-admin-set')
      cachedSelectors.initialized = true
    }
  }

  function isDefaultRightsStatementRequired() {
    if (StepperState.skipValidation || !StepperState.validationData) return false
    var missing = StepperState.validationData.missingRequired
    if (!missing || !Array.isArray(missing)) return false
    return missing.some(function (item) { return item && item.field === 'rights_statement' })
  }

  function didSkipValidation() {
    return StepperState.skipValidation === true
  }

  function updateStep2RightsStatementUI() {
    var required = isDefaultRightsStatementRequired()
    var skipped = didSkipValidation()
    var $alert = $('#default-rights-required-alert')
    var $hint = $('#default-rights-skipped-hint')
    var $label = $('.default-rights-statement-label')
    var $optionalSettings = $('#optional-settings')

    if ($alert.length) {
      $alert.toggle(required)
    }
    if ($hint.length) {
      $hint.toggle(skipped && !required)
    }
    if ($label.length) {
      var $asterisk = $label.find('.text-danger.default-rights-required-asterisk')
      if (required && !$asterisk.length) {
        $label.append(' <span class="text-danger default-rights-required-asterisk">*</span>')
      } else if (!required && $asterisk.length) {
        $asterisk.remove()
      }
    }
    if ((required || skipped) && $optionalSettings.length && !$optionalSettings.hasClass('show')) {
      $optionalSettings.addClass('show')
    }
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
      initCachedSelectors()
      var name = (cachedSelectors.nameInput.length ? cachedSelectors.nameInput.val() : '').trim()
      var adminSetId = (cachedSelectors.adminSetSelect.length ? cachedSelectors.adminSetSelect.val() : '').trim()
      var rightsRequired = isDefaultRightsStatementRequired()
      var rightsValue = $('select[name="importer[parser_fields][rights_statement]"]').val()
      var hasRights = rightsValue && rightsValue.length > 0

      canProceed = name.length > 0 && adminSetId.length > 0 && (!rightsRequired || hasRights)
      StepperState.settings.name = name || StepperState.settings.name
      StepperState.adminSetId = adminSetId || StepperState.adminSetId
      $('.step-content[data-step="2"] .step-next-btn').prop('disabled', !canProceed)
      updateStep2RightsStatementUI()
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
          '<p><span class="text-muted small">' + type + ':</span> ' + escapeHtml(f.name) + ' (' + escapeHtml(f.size) + ')' + fromZip + '</p>'
        )
      })
      .join('')
    $('.review-files').html(filesHtml)

    // Records
    var totalItems = 0
    var recordsHtml
    if (data) {
      totalItems = data.collections.length + data.works.length + data.fileSets.length
      recordsHtml =
        '<p>' +
        totalItems +
        ' total — ' +
        data.collections.length +
        ' collections, ' +
        data.works.length +
        ' works, ' +
        data.fileSets.length +
        ' file sets</p>'
    } else {
      recordsHtml = '<p class="text-muted">Validation was skipped — record counts unavailable</p>'
    }
    $('.review-records').html(recordsHtml)

    // Settings - get admin set name from DOM first, then fallback to state
    var $currentAdminSet = $('#importer-admin-set')
    var adminSetName = 'Not selected'
    if ($currentAdminSet.length) {
      var selectedText = $currentAdminSet.find('option:selected').text().trim()
      var selectedValue = $currentAdminSet.val()
      if (selectedValue && selectedValue !== '' && selectedText !== 'Select an admin set...') {
        adminSetName = selectedText
      }
    }
    if (adminSetName === 'Not selected' && StepperState.adminSetName) {
      adminSetName = StepperState.adminSetName
    }
    var visibilityLabels = {
      open: 'Public',
      authenticated: 'Institution',
      restricted: 'Private'
    }
    var visibilityName = visibilityLabels[settings.visibility]

    var settingsHtml =
      '<p><span class="text-muted small">Name:</span> ' +
      escapeHtml(settings.name) +
      '</p>' +
      '<p><span class="text-muted small">Admin Set:</span> ' +
      adminSetName +
      '</p>' +
      '<p><span class="text-muted small">Visibility:</span> ' +
      visibilityName +
      '</p>'

    if (settings.rightsStatement) {
      settingsHtml += '<p><span class="text-muted small">Rights:</span> ' + settings.rightsStatement + '</p>'
    }
    if (settings.limit) {
      settingsHtml += '<p><span class="text-muted small">Limit:</span> first ' + settings.limit + ' records</p>'
    }

    $('.review-settings').html(settingsHtml)

    // Warnings
    if (data && data.hasWarnings) {
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
    if (data && totalItems > CONSTANTS.IMPORT_SIZE_MODERATE) {
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

    // Disable the file input so raw files aren't sent with the form
    $('#file-input').prop('disabled', true)

    // Add uploaded file IDs as hidden inputs
    StepperState.uploadedFiles.forEach(function (f) {
      if (f.uploadId) {
        $form.append('<input type="hidden" name="uploaded_files[]" value="' + f.uploadId + '">')
      }
    })

    // Submit the form so the request hits create_v2 and creates the importer / enqueues job
    $form[0].submit()
  }

  // Look up mock validation data from cached demo scenarios JSON
  function getMockValidationData() {
    var scenario = StepperState.demoScenario || 'warning_combined'
    var data = StepperState.demoScenariosData
    if (!data || !data.scenarios || !data.scenarios[scenario]) return null
    return data.scenarios[scenario].response
  }

  // ============================================================================
  // NOTIFICATION FUNCTIONS
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
