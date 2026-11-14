const screenshotImage = document.querySelector('.dashboard img');
const screenshotToggle = document.querySelector('.screenshot-toggle');

/** Show the given screenshot appearance and update the button state. */
function showScreenshot(appearance) {
  screenshotImage.src = appearance === 'dark' ? 'dark.png' : 'light.png';
  screenshotToggle.setAttribute('aria-pressed', String(appearance === 'dark'));
  screenshotToggle.title = appearance === 'dark' ? 'Switch to light screenshot' : 'Switch to dark screenshot';
}

/** Toggle the screenshot appearance for the current page visit. */
function chooseScreenshot() {
  showScreenshot(screenshotToggle.getAttribute('aria-pressed') === 'true' ? 'light' : 'dark');
}

showScreenshot('light');
screenshotToggle.addEventListener('click', chooseScreenshot);
screenshotToggle.hidden = false;
