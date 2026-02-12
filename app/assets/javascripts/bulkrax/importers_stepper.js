// Bulk Import Stepper - Multi-step wizard for CSV/ZIP imports
// Handles file uploads, validation, settings, and review steps

;(function ($) {
  'use strict'

  // State management
  var StepperState = {
    currentStep: 1,
    uploadedFiles: [],
    uploadState: 'empty', // 'empty' | 'csv_only' | 'zip_files_only' | 'zip_with_csv' | 'csv_and_zip'
    validated: false,
    validationData: null,
    warningsAcked: false,
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

  // Initialize on page load
  function initBulkImportStepper() {
    if ($('#bulk-import-stepper-form').length === 0) {
      return
    }

    bindEvents()
    updateStepperUI()
    initVisibilityCards()
    setDefaultImportName()
  }

  // Bind all event handlers
  function bindEvents() {
    // File upload - main dropzone
    $('.upload-dropzone').on('click', function (e) {
      if (e.target.id === 'file-input') return

      StepperState.isAddingFiles = false
      $('#file-input').trigger('click')
    })

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
        // Create a new DataTransfer to hold the files
        var dataTransfer = new DataTransfer()

        // Add dropped files (up to 2 total)
        var maxFiles = Math.min(droppedFiles.length, 2)
        for (var i = 0; i < maxFiles; i++) {
          dataTransfer.items.add(droppedFiles[i])
        }

        $('#file-input')[0].files = dataTransfer.files

        // Set flag based on whether we already have files
        StepperState.isAddingFiles = false // Drag and drop replaces files

        handleFileSelect(StepperState.isAddingFiles)
        StepperState.isAddingFiles = false

        // Show warning if more than 2 files were dropped
        if (droppedFiles.length > 2) {
          showNotification(
            'Only the first 2 files have been uploaded. You can upload up to 2 files (1 CSV and 1 ZIP).'
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
        var dataTransfer = new DataTransfer()
        dataTransfer.items.add(droppedFiles[0])

        $('#file-input')[0].files = dataTransfer.files

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
    $('.step-circle').on('dblclick', function () {
      var $panel = $('.demo-scenarios')
      $panel.toggle()
      if ($panel.is(':visible')) {
        loadDemoScenariosData(function () {}) // Prefetch
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

    // Step navigation
    $('.step-next-btn').on('click', function () {
      var nextStep = parseInt($(this).data('next-step'))
      goToStep(nextStep)
    })

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
    $('#bulkrax_importer_name').on('input', function () {
      StepperState.settings.name = $(this).val()
      updateStepNavigation()
    })

    $('#bulkrax_importer_admin_set_id').on('change', function () {
      StepperState.settings.adminSetId = $(this).val()
      updateStepNavigation()
    })

    $('#bulkrax_importer_limit').on('input', function () {
      StepperState.settings.limit = $(this).val()
    })

    // Remove file button (using event delegation since rows are dynamic)
    $(document).on('click', '.file-remove-btn', function() {
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
    $('#skip-validation-checkbox').on('change', function() {
      StepperState.skipValidation = $(this).is(':checked')
      updateStepNavigation()
    })
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
    return ext === '.csv' || ext === '.zip'
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
      messages.forEach(function(msg) {
        html += '<li>' + msg.replace(/\n/g, '<br>') + '</li>'
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
      i < files.length && StepperState.uploadedFiles.length < 2;
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
        StepperState.uploadedFiles.length >= 2 &&
        files.length > addedFiles.length + rejectedFiles.length
      ) {
        messages.push('Maximum of 2 files reached (1 CSV and 1 ZIP).')
      }

      showFileUploadError(messages)
    } else if (files.length > addedFiles.length) {
      showFileUploadError([
        'Maximum of 2 files allowed (1 CSV and 1 ZIP). Only the first ' +
          addedFiles.length +
          ' file(s) were added.'
      ])
    } else {
      clearFileUploadError()
    }

    updateUploadState()
    renderUploadedFiles()
  }

  // Fetch and cache demo scenarios JSON from server
  function loadDemoScenariosData(callback) {
    if (StepperState.demoScenariosData) {
      callback(StepperState.demoScenariosData)
      return
    }

    $.ajax({
      url: '/importers/v2/demo_scenarios',
      method: 'GET',
      dataType: 'json',
      success: function (data) {
        StepperState.demoScenariosData = data
        callback(data)
      },
      error: function () {
        console.warn('Failed to load demo scenarios')
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

  // Update upload state based on files
  function updateUploadState() {
    var files = StepperState.uploadedFiles
    if (files.length === 0) {
      StepperState.uploadState = 'empty'
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
      StepperState.uploadState = 'zip_with_csv'
    } else if (hasZip && !hasCsvInZip && !hasStandaloneCsv) {
      StepperState.uploadState = 'zip_files_only'
    } else if (hasStandaloneCsv && hasZip) {
      StepperState.uploadState = 'csv_and_zip'
    } else if (hasStandaloneCsv && !hasZip) {
      StepperState.uploadState = 'csv_only'
    } else {
      StepperState.uploadState = 'empty'
    }
  }

  // Render uploaded files
  function renderUploadedFiles() {
    var state = StepperState.uploadState
    var files = StepperState.uploadedFiles

    if (state === 'empty') {
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
    if (state === 'zip_with_csv') {
      infoMessage =
        '<div class="upload-info"><span class="fa fa-info-circle"></span> Single package with CSV and files</div>'
    } else if (state === 'csv_only') {
      infoMessage =
        '<div class="upload-info"><span class="fa fa-info-circle"></span> No ZIP uploaded — files will be matched from server paths or you can add more files</div>'
    } else if (state === 'zip_files_only') {
      infoMessage =
        '<div class="upload-info"><span class="fa fa-info-circle"></span> ZIP file uploaded — validation will check for CSV content</div>'
    } else if (state === 'csv_and_zip') {
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

    // Enable validate button if we have a CSV OR a ZIP file (which might contain a CSV)
    $('#validate-btn').prop(
      'disabled',
      !(hasCsv || hasZip) || StepperState.validated
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
      name +
      '</div>' +
      '<div class="file-subtitle">' +
      subtitle +
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
    StepperState.uploadState = 'empty'
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
        StepperState.validationData = mockData

        renderValidationResults(mockData)
        $btn.html('<span class="fa fa-check-circle"></span> Validated')
        updateStepNavigation()
      }, 2000)
    } else {
      // Real AJAX call for actual file uploads
      var formData = new FormData($('#bulk-import-stepper-form')[0])

      $.ajax({
        url: '/importers/v2/validate',
        method: 'POST',
        data: formData,
        processData: false,
        contentType: false,
        success: function (data) {
          StepperState.validated = true
          StepperState.validationData = data
          renderValidationResults(data)
          $btn.html('<span class="fa fa-check-circle"></span> Validated')
          updateStepNavigation()
        },
        error: function (xhr) {
          var errorMsg = 'Validation failed. Please try again.'
          if (xhr.responseJSON && xhr.responseJSON.error) {
            errorMsg = xhr.responseJSON.error
          }
          showNotification(errorMsg)
          $btn
            .prop('disabled', false)
            .html('<span class="fa fa-file-text"></span> Validate Files')
        }
      })
    }
  }

  // Render validation results
  function renderValidationResults(data) {
    $('.validation-results').show()

    // Import size gauge
    renderImportSizeGauge(data.totalItems)

    // Validation status accordion
    renderValidationAccordions(data)

    // Import summary
    renderImportSummary(data)

    // Warning acknowledgment
    if (data.hasWarnings) {
      $('.warning-acknowledgment').show()
    }
  }

  // Render import size gauge
  function renderImportSizeGauge(count) {
    var pct, color, zone, msg, cardClass

    if (count <= 100) {
      pct = (count / 100) * 33
      color = 'gauge-marker-optimal'
      zone = 'Optimal'
      msg = 'Great! Smaller imports are easier to validate and troubleshoot.'
      cardClass = 'gauge-card-optimal'
    } else if (count <= 500) {
      pct = 33 + ((count - 100) / 400) * 33
      color = 'gauge-marker-moderate'
      zone = 'Moderate'
      msg =
        'Consider splitting into smaller batches for easier error resolution.'
      cardClass = 'gauge-card-moderate'
    } else {
      pct = Math.min(66 + ((count - 500) / 500) * 34, 100)
      color = 'gauge-marker-large'
      zone = 'Large'
      msg =
        'Large imports take longer and are harder to debug. We strongly recommend splitting into batches of 100 or fewer.'
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
      '<span>0</span><span>100</span><span>500</span><span>1000+</span>' +
      '</div>' +
      '<p class="gauge-message">' +
      msg +
      '</p>' +
      '</div>'

    $('.import-size-gauge').html(html)
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
    // Use main status severity for all issue accordions to maintain consistent coloring
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
          content += '<ul>'
          issue.items.forEach(function (item) {
            var msg = item.message ? ' — ' + item.message : ''
            content +=
              '<li>• <strong>' + item.field + '</strong>' + msg + '</li>'
          })
          content += '</ul>'
        }

        if (issue.details) {
          content += '<p class="small">' + issue.details + '</p>'
        }

        $wrapper.append(
          createAccordion(
            issue.title,
            issue.icon,
            status.severity,
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
          $content.slideUp(200)
          $chevron.removeClass('fa-chevron-down').addClass('fa-chevron-right')
          $item.removeClass('accordion-open')
        } else {
          $content.slideDown(200)
          $chevron.removeClass('fa-chevron-right').addClass('fa-chevron-down')
          $item.addClass('accordion-open')
        }
      })
  }

  // Render import summary
  function renderImportSummary(data) {
    $('.summary-card-collections .summary-number').text(data.collections.length)
    $('.summary-card-works .summary-number').text(data.works.length)
    $('.summary-card-filesets .summary-number').text(data.fileSets.length)

    // Hierarchy accordions
    var $container = $('.hierarchy-accordions')
    $container.empty()

    // Import hierarchy — collections, nested items, and standalone works in one tree
    var allItems = data.collections.concat(data.works)
    var topLevelCollections = data.collections.filter(function (c) {
      return !c.parentId
    })
    var orphanWorks = data.works.filter(function (w) {
      return !w.parentId
    })
    var hierarchyContent =
      '<div class="hierarchy-tree">' +
      topLevelCollections
        .map(function (c) {
          return renderTreeItem(c, allItems)
        })
        .join('') +
      orphanWorks
        .map(function (w) {
          return renderTreeItem(w, allItems)
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

  // Render tree item
  function renderTreeItem(item, allItems, depth) {
    depth = depth || 0
    var children = allItems.filter(function (i) {
      return i.parentId === item.id
    })
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

    var html =
      '<div class="tree-item" data-item-id="' +
      item.id +
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
      item.title +
      '</span>' +
      count +
      '</div>'

    if (hasChildren) {
      html +=
        '<div class="tree-children" style="display: none;">' +
        children
          .map(function (c) {
            return renderTreeItem(c, allItems, depth + 1)
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
            $children.slideUp(200)
            $chevron.removeClass('fa-chevron-down').addClass('fa-chevron-right')
          } else {
            $children.slideDown(200)
            $chevron.removeClass('fa-chevron-right').addClass('fa-chevron-down')
          }
        }
      })
  }

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

  // Navigate to step
  function goToStep(stepNum) {
    StepperState.currentStep = stepNum
    updateStepperUI()

    // Scroll to top
    $('html, body').animate({ scrollTop: 0 }, 300)

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
      var canProceed = StepperState.skipValidation ||
        (StepperState.validated &&
        StepperState.validationData.isValid &&
        (!StepperState.validationData.hasWarnings || StepperState.warningsAcked))

      $('.step-content[data-step="1"] .step-next-btn').prop('disabled', !canProceed)
    } else if (step === 2) {
      var canProceed =
        StepperState.settings.name && StepperState.settings.adminSetId
      $('.step-content[data-step="2"] .step-next-btn').prop(
        'disabled',
        !canProceed
      )
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

    // Settings
    var adminSetName = $(
      '#bulkrax_importer_admin_set_id option:selected'
    ).text()
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
    if (totalItems > 500) {
      $('.large-import-warning').show()
    } else {
      $('.large-import-warning').hide()
    }
  }

  // Handle import submission
  function handleImportSubmit() {
    var $btn = $('#start-import-btn')
    $btn
      .prop('disabled', true)
      .html('<span class="fa fa-spinner fa-spin"></span> Starting...')

    // Simulate submission (replace with real form submit)
    setTimeout(function () {
      showSuccessState()
    }, 2500)

    // For real submission, just let the form submit normally or use AJAX
    // $('#bulk-import-stepper-form')[0].submit();
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

  // Utility: format file size
  function formatFileSize(bytes) {
    if (bytes === 0) return '0 Bytes'
    var k = 1024
    var sizes = ['Bytes', 'KB', 'MB', 'GB']
    var i = Math.floor(Math.log(bytes) / Math.log(k))
    return Math.round((bytes / Math.pow(k, i)) * 100) / 100 + ' ' + sizes[i]
  }

  function showNotification(message, type) {
    type = type || 'info' // 'error', 'warning', 'info'

    var icons = {
      error: 'fa-times-circle',
      warning: 'fa-exclamation-triangle',
      info: 'fa-info-circle'
    }

    var $notification = $(
      '<div class="upload-notification notification-' + type + '">' +
      '<span class="fa ' + icons[type] + ' upload-notification-icon"></span>' +
      '<div class="upload-notification-content">' + message + '</div>' +
      '<span class="fa fa-times upload-notification-close"></span>' +
      '</div>'
    )

    $('#upload-notifications').append($notification)

    // Click to dismiss
    $notification.find('.upload-notification-close').on('click', function() {
      $notification.fadeOut(300, function() {
        $(this).remove()
      })
    })
  }

  // Initialize on document ready and turbolinks load
  $(document).on('ready turbolinks:load', initBulkImportStepper)
})(jQuery)
