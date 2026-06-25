document.querySelectorAll("[data-quiz]").forEach((quiz) => {
  const button = quiz.querySelector("button");
  const answer = quiz.querySelector(".answer");
  if (!button || !answer) {
    return;
  }

  button.addEventListener("click", () => {
    const selected = quiz.querySelector("input[type='radio']:checked");
    if (!selected) {
      answer.textContent = "Choose an answer first.";
      return;
    }

    answer.textContent = selected.dataset.correct === "true"
      ? "Correct. Use that pattern in the next exercise."
      : "Not quite. Re-check the telemetry path and the system of record.";
  });
});
