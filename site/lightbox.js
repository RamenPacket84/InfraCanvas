(() => {
  const dialog = document.querySelector(".lightbox");
  if (!dialog || typeof dialog.showModal !== "function") {
    return;
  }

  const source = dialog.querySelector("source");
  const image = document.getElementById("lightbox-image");
  const caption = document.getElementById("lightbox-caption");
  const closeButton = dialog.querySelector(".lightbox-close");
  const links = document.querySelectorAll(".screenshot-open");

  const fill = (link) => {
    const thumb = link.querySelector("img");
    const label = link.parentElement.querySelector("figcaption");
    source.srcset = link.dataset.webp || "";
    image.src = link.getAttribute("href");
    image.width = Number(link.dataset.width) || 1600;
    image.height = Number(link.dataset.height) || 938;
    image.alt = thumb ? thumb.alt : "";
    caption.textContent = label ? label.textContent : "";
  };

  const clear = () => {
    source.removeAttribute("srcset");
    image.removeAttribute("src");
    image.alt = "";
    caption.textContent = "";
  };

  links.forEach((link) => {
    link.setAttribute("aria-haspopup", "dialog");
    link.addEventListener("click", (event) => {
      event.preventDefault();
      fill(link);
      dialog.showModal();
    });
  });

  closeButton.addEventListener("click", () => {
    dialog.close();
  });

  dialog.addEventListener("click", (event) => {
    if (event.target === dialog) {
      dialog.close();
    }
  });

  dialog.addEventListener("close", clear);
})();
