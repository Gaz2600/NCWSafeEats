// ====== CONFIG ======
const DATA_URL = './data/inspection_data.json'; // JSON file lives in /beta/data/

let inspections = [];
let filtered = [];

// Run once DOM is ready
document.addEventListener('DOMContentLoaded', () => {
  loadInspectionData();
  wireUpControls();
});

// ----- Load JSON -----
async function loadInspectionData() {
  try {
    console.log('Loading inspection data from:', DATA_URL);
    const res = await fetch(DATA_URL);

    if (!res.ok) {
      console.error('Failed to fetch JSON:', res.status, res.statusText);
      showError('Could not load inspection data file. Showing no results.');
      return;
    }

    inspections = await res.json();
    console.log('Loaded inspection records:', inspections.length);

    populateCityFilter(inspections);
    filtered = inspections.slice();
    renderResults();
  } catch (err) {
    console.error('Error loading inspection data:', err);
    showError('Could not load inspection data file. Showing no results.');
  }
}

// ----- UI Wiring -----
function wireUpControls() {
  const searchInput   = document.getElementById('searchInput');
  const cityFilter    = document.getElementById('cityFilter');
  const statusFilter  = document.getElementById('statusFilter');
  const sortSelect    = document.getElementById('sortSelect');
  const top10Toggle   = document.getElementById('top10Toggle');

  if (searchInput) {
    searchInput.addEventListener('input', () => {
      applyFilters();
    });
  }

  if (cityFilter) {
    cityFilter.addEventListener('change', applyFilters);
  }

  if (statusFilter) {
    statusFilter.addEventListener('change', applyFilters);
  }

  if (sortSelect) {
    sortSelect.addEventListener('change', applyFilters);
  }

  if (top10Toggle) {
    top10Toggle.addEventListener('change', applyFilters);
  }
}

// ----- Filters & Sorting -----
function applyFilters() {
  const searchInput   = document.getElementById('searchInput');
  const cityFilter    = document.getElementById('cityFilter');
  const statusFilter  = document.getElementById('statusFilter');
  const sortSelect    = document.getElementById('sortSelect');
  const top10Toggle   = document.getElementById('top10Toggle');

  const searchTerm = (searchInput?.value || '').toLowerCase().trim();
  const cityValue  = cityFilter?.value || 'all';
  const statusVal  = statusFilter?.value || 'all';
  const sortVal    = sortSelect?.value || 'score-desc';
  const onlyTop10  = !!top10Toggle?.checked;

  let data = inspections.slice();

  if (searchTerm) {
    data = data.filter(r =>
      (r.name || '').toLowerCase().includes(searchTerm) ||
      (r.address || '').toLowerCase().includes(searchTerm)
    );
  }

  if (cityValue !== 'all') {
    data = data.filter(r => (r.city || '').toLowerCase() === cityValue.toLowerCase());
  }

  if (statusVal !== 'all') {
    data = data.filter(r => (r.status || '').toLowerCase() === statusVal.toLowerCase());
  }

  // sort
  data.sort((a, b) => {
    const scoreA = a.score ?? 0;
    const scoreB = b.score ?? 0;

    if (sortVal === 'score-asc')  return scoreA - scoreB;
    if (sortVal === 'score-desc') return scoreB - scoreA;

    // default: name asc
    return (a.name || '').localeCompare(b.name || '');
  });

  if (onlyTop10) {
    data = data.slice(0, 10);
  }

  filtered = data;
  renderResults();
}

// ----- Populate City Filter -----
function populateCityFilter(records) {
  const cityFilter = document.getElementById('cityFilter');
  if (!cityFilter) return;

  const cities = Array.from(
    new Set(
      records
        .map(r => (r.city || '').trim())
        .filter(Boolean)
    )
  ).sort((a, b) => a.localeCompare(b));

  // Clear existing except "All"
  cityFilter.innerHTML = '';
  const allOpt = document.createElement('option');
  allOpt.value = 'all';
  allOpt.textContent = 'All cities';
  cityFilter.appendChild(allOpt);

  cities.forEach(city => {
    const opt = document.createElement('option');
    opt.value = city;
    opt.textContent = city;
    cityFilter.appendChild(opt);
  });
}

// ----- Rendering -----
function renderResults() {
  const container = document.getElementById('resultsContainer');
  const summary   = document.getElementById('summaryText');

  if (!container) return;

  container.innerHTML = '';

  if (!filtered.length) {
    container.innerHTML = '<p class="empty-state">No inspections match your filters.</p>';
    if (summary) summary.textContent = 'No results.';
    return;
  }

  if (summary) {
    summary.textContent = `${filtered.length} location${filtered.length === 1 ? '' : 's'} shown`;
  }

  filtered.forEach(item => {
    const card = document.createElement('div');
    card.className = 'inspection-card';

    card.innerHTML = `
      <div class="card-header">
        <div>
          <h2 class="restaurant-name">${escapeHtml(item.name || 'Unknown')}</h2>
          <div class="restaurant-meta">
            <span>${escapeHtml(item.city || '')}</span> ·
            <span>${escapeHtml(item.address || '')}</span>
          </div>
        </div>
        <div class="score-pill ${scoreClass(item.score)}">
          ${item.score ?? '–'}
        </div>
      </div>
      <div class="card-body">
        <div class="badge-row">
          <span class="badge status-${(item.status || 'unknown').toLowerCase()}">
            ${escapeHtml(item.status || 'Unknown')}
          </span>
          ${item.last_inspection_date ? `
            <span class="badge date-badge">
              Last inspection: ${escapeHtml(item.last_inspection_date)}
            </span>` : ''}
        </div>
        ${item.violations && item.violations.length ? `
          <div class="violations">
            <div class="violations-title">Recent violations:</div>
            <ul>
              ${item.violations.slice(0,3).map(v => `<li>${escapeHtml(v)}</li>`).join('')}
            </ul>
          </div>
        ` : `
          <div class="violations none">No violations listed.</div>
        `}
      </div>
    `;

    container.appendChild(card);
  });
}

// ----- Helpers -----
function showError(message) {
  const msgEl = document.getElementById('errorMessage');
  if (msgEl) {
    msgEl.textContent = message;
    msgEl.style.display = 'block';
  } else {
    alert(message);
  }
}

function scoreClass(score) {
  if (score === null || score === undefined) return 'score-unknown';
  if (score >= 95) return 'score-great';
  if (score >= 90) return 'score-good';
  if (score >= 80) return 'score-ok';
  return 'score-poor';
}

function escapeHtml(str) {
  return String(str)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

