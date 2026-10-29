"use strict";

// Solo filtra datos estáticos del documento; no hace peticiones ni guarda datos.
const searchInput = document.querySelector("#vehicle-search");
const brandButtons = [...document.querySelectorAll("[data-brand]")]
  .filter((element) => element.tagName === "BUTTON");
const vehicleRows = [...document.querySelectorAll("#vehicles tr")];
const resultCount = document.querySelector("#result-count");
const emptyState = document.querySelector("#empty-state");
let selectedBrand = "Todas";

function normalize(text) {
  return text.normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLowerCase().trim();
}

function filterVehicles() {
  const query = normalize(searchInput.value);
  let visible = 0;

  for (const row of vehicleRows) {
    const matchesBrand = selectedBrand === "Todas" || row.dataset.brand === selectedBrand;
    const matchesSearch = normalize(row.textContent).includes(query);
    row.hidden = !(matchesBrand && matchesSearch);
    if (!row.hidden) visible += 1;
  }

  resultCount.textContent = `${visible} ${visible === 1 ? "vehículo" : "vehículos"} en esta vista`;
  emptyState.hidden = visible !== 0;
}

for (const button of brandButtons) {
  button.addEventListener("click", () => {
    selectedBrand = button.dataset.brand;
    for (const candidate of brandButtons) {
      const selected = candidate === button;
      candidate.classList.toggle("selected", selected);
      candidate.setAttribute("aria-pressed", String(selected));
    }
    filterVehicles();
  });
}

searchInput.addEventListener("input", filterVehicles);
filterVehicles();
