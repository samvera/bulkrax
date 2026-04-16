(function() {
  'use strict';

  var fieldIndex = 1000;

  function init() {
    var table = document.getElementById('field-mappings-table');
    if (!table) return;

    // Initialize Bootstrap tooltips
    if (typeof jQuery !== 'undefined' && jQuery.fn.tooltip) {
      jQuery('[data-toggle="tooltip"]').tooltip();
    }

    // Add field button
    var addBtn = document.getElementById('add-field-btn');
    if (addBtn) {
      addBtn.addEventListener('click', addFieldRow);
    }

    // Add missing fields button
    var addMissingBtn = document.getElementById('add-missing-fields-btn');
    if (addMissingBtn) {
      addMissingBtn.addEventListener('click', addMissingFields);
    }

    // Delegate events on table
    table.addEventListener('click', function(e) {
      var toggle = e.target.closest('.expand-toggle');
      var remove = e.target.closest('.remove-field-btn');

      if (toggle) {
        toggleAdvanced(toggle);
      } else if (remove) {
        removeFieldRow(remove);
      }
    });

    // Split checkbox toggle
    table.addEventListener('change', function(e) {
      if (e.target.classList.contains('split-checkbox')) {
        var wrapper = e.target.closest('td').querySelector('.split-regex-wrapper');
        if (wrapper) {
          wrapper.style.display = e.target.checked ? '' : 'none';
        }
        updateSplitPreview(e.target.closest('td'));
      }
    });

    // Regex preview on input
    document.addEventListener('input', function(e) {
      if (e.target.classList.contains('regex-input')) {
        var splitCell = e.target.closest('.split-cell');
        if (splitCell) {
          updateSplitPreview(splitCell);
        } else {
          updateRegexPreview(e.target);
        }
      }
    });

    // Initialize previews for existing values
    var splitCells = document.querySelectorAll('.split-cell');
    for (var i = 0; i < splitCells.length; i++) {
      updateSplitPreview(splitCells[i]);
    }

    var regexInputs = document.querySelectorAll('.regex-input:not(.split-cell .regex-input)');
    for (var i = 0; i < regexInputs.length; i++) {
      if (regexInputs[i].value) {
        updateRegexPreview(regexInputs[i]);
      }
    }
  }

  function addFieldRow() {
    var template = document.getElementById('field-row-template');
    if (!template) return;

    var html = template.innerHTML.replace(/__INDEX__/g, fieldIndex++);
    var tbody = document.querySelector('#field-mappings-table tbody');
    tbody.insertAdjacentHTML('beforeend', html);
  }

  function addMissingFields() {
    var btn = document.getElementById('add-missing-fields-btn');
    if (!btn) return;

    var missingFields = JSON.parse(btn.getAttribute('data-missing-fields'));
    var template = document.getElementById('field-row-template');
    var tbody = document.querySelector('#field-mappings-table tbody');
    if (!template || !tbody) return;

    // Get existing field names to avoid duplicates
    var existingNames = {};
    var nameInputs = tbody.querySelectorAll('.field-name-input');
    for (var i = 0; i < nameInputs.length; i++) {
      existingNames[nameInputs[i].value.trim()] = true;
    }

    missingFields.forEach(function(fieldName) {
      if (existingNames[fieldName]) return;

      var html = template.innerHTML.replace(/__INDEX__/g, fieldIndex++);
      tbody.insertAdjacentHTML('beforeend', html);

      // Set the field name and from values on the newly added row
      var rows = tbody.querySelectorAll('tr.field-row');
      var lastRow = rows[rows.length - 1];
      var nameInput = lastRow.querySelector('.field-name-input');
      if (nameInput) {
        nameInput.value = fieldName;
      }
      // Default the "from" to the same name
      var fromInput = lastRow.querySelector('input[name$="[from]"]');
      if (fromInput) {
        fromInput.value = fieldName;
      }
    });

    sortTableRows();
    btn.style.display = 'none';
  }

  function sortTableRows() {
    var tbody = document.querySelector('#field-mappings-table tbody');
    if (!tbody) return;

    // Collect pairs of [field-row, advanced-row]
    var pairs = [];
    var fieldRows = tbody.querySelectorAll('tr.field-row');
    for (var i = 0; i < fieldRows.length; i++) {
      var row = fieldRows[i];
      var idx = row.getAttribute('data-index');
      var advancedRow = tbody.querySelector('tr.advanced-row[data-index="' + idx + '"]');
      var name = (row.querySelector('.field-name-input') || {}).value || '';
      pairs.push({ name: name.toLowerCase(), fieldRow: row, advancedRow: advancedRow });
    }

    pairs.sort(function(a, b) {
      return a.name.localeCompare(b.name);
    });

    pairs.forEach(function(pair) {
      tbody.appendChild(pair.fieldRow);
      if (pair.advancedRow) {
        tbody.appendChild(pair.advancedRow);
      }
    });
  }

  function removeFieldRow(button) {
    var row = button.closest('tr.field-row');
    if (!row) return;

    var idx = row.getAttribute('data-index');
    var advancedRow = document.querySelector('tr.advanced-row[data-index="' + idx + '"]');

    row.remove();
    if (advancedRow) advancedRow.remove();
  }

  function toggleAdvanced(button) {
    var row = button.closest('tr.field-row');
    if (!row) return;

    var idx = row.getAttribute('data-index');
    var advancedRow = document.querySelector('tr.advanced-row[data-index="' + idx + '"]');
    if (!advancedRow) return;

    var isVisible = advancedRow.style.display !== 'none';
    advancedRow.style.display = isVisible ? 'none' : '';

    var icon = button.querySelector('.fa');
    if (icon) {
      icon.classList.toggle('fa-chevron-down', isVisible);
      icon.classList.toggle('fa-chevron-up', !isVisible);
    }
  }

  function updateSplitPreview(cell) {
    var checkbox = cell.querySelector('.split-checkbox');
    var regexInput = cell.querySelector('.regex-input');
    var preview = cell.querySelector('.regex-preview');
    if (!preview) return;

    if (!checkbox || !checkbox.checked) {
      preview.textContent = '';
      preview.className = 'regex-preview text-muted';
      return;
    }

    var pattern = regexInput ? regexInput.value.trim() : '';
    if (!pattern) {
      preview.textContent = 'Using default split';
      preview.className = 'regex-preview text-muted';
      return;
    }

    // Validate and describe the custom pattern
    var jsPattern = pattern.replace(/^\(\?[a-z\-]*:(.*)\)$/, '$1');

    try {
      new RegExp(jsPattern);
    } catch (e) {
      preview.textContent = 'Invalid regex: ' + e.message;
      preview.className = 'regex-preview text-danger';
      return;
    }

    var description = describeRegex(jsPattern);
    if (description) {
      preview.textContent = description;
      preview.className = 'regex-preview text-muted';
    } else {
      preview.textContent = 'Does not look like a split delimiter pattern';
      preview.className = 'regex-preview text-warning';
    }
  }

  function updateRegexPreview(input) {
    var preview = input.parentElement.querySelector('.regex-preview');
    if (!preview) return;

    var pattern = input.value.trim();
    if (!pattern) {
      preview.textContent = '';
      preview.className = 'regex-preview text-muted';
      return;
    }

    // Strip Ruby regex wrapper (?-mix:...) or (?i-mx:...) etc.
    var jsPattern = pattern.replace(/^\(\?[a-z\-]*:(.*)\)$/, '$1');

    try {
      new RegExp(jsPattern);
    } catch (e) {
      preview.textContent = 'Invalid regex: ' + e.message;
      preview.className = 'regex-preview text-danger';
      return;
    }

    var description = describeRegex(jsPattern);
    if (description) {
      preview.textContent = description;
      preview.className = 'regex-preview text-muted';
    } else {
      preview.textContent = 'Does not look like a split delimiter pattern';
      preview.className = 'regex-preview text-warning';
    }
  }

  function describeRegex(pattern) {
    // Single delimiter character: |  ;  ,  :  \t
    if (/^[|;,:\t]$/.test(pattern)) {
      return 'Splits on ' + describeLiteral(pattern);
    }

    // Escaped single delimiter: \| \; etc.
    if (/^\\[|;,:.\/]$/.test(pattern)) {
      return 'Splits on literal ' + describeLiteral(pattern.charAt(1));
    }

    // Normalize double backslashes to single for matching: \\s → \s
    var normalized = pattern.replace(/\\\\/g, '\\');

    // Character class with optional surrounding whitespace: \s*[|;]\s*
    if (/^(\\s[*+])?(\[([^\]]+)\]|[|;,:])(\\s[*+])?$/.test(normalized)) {
      var charMatch = normalized.match(/\[([^\]]+)\]/);
      var delim = charMatch ? charMatch[1] : normalized.replace(/\\s[*+]/g, '');
      var ws = /\\s/.test(normalized) ? ' (with surrounding whitespace)' : '';
      return 'Splits on ' + describeLiteral(delim) + ws;
    }

    // Alternation group of delimiters: (;|,|\|)
    if (/^\(([^)]+)\)$/.test(pattern)) {
      var alts = pattern.slice(1, -1).split('|');
      if (alts.every(function(a) { return a.replace(/^\\/, '').length <= 2; })) {
        return "Splits on " + alts.map(function(a) { return describeLiteral(a.replace(/^\\/, '')); }).join(' or ');
      }
    }

    // Simple literal string delimiter
    if (/^[a-zA-Z0-9_ ]{1,10}$/.test(pattern)) {
      return "Splits on literal '" + pattern + "'";
    }

    // Not a recognized split pattern
    return null;
  }

  function describeLiteral(char) {
    var names = { '|': 'pipe (|)', ';': 'semicolon (;)', ',': 'comma (,)', ':': 'colon (:)' };
    return names[char] || "'" + char + "'";
  }

  // Support both Turbolinks and standard page load
  if (typeof Turbolinks !== 'undefined') {
    document.addEventListener('turbolinks:load', init);
  } else if (typeof Turbo !== 'undefined') {
    document.addEventListener('turbo:load', init);
  } else {
    document.addEventListener('DOMContentLoaded', init);
  }
})();
