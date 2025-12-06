import QtQuick

QtObject {
  id: root

  // Migrate from version < 26 to version 26
  // Replaces old calendar-card and banner-card with calendar-header-card and calendar-month-card
  function migrate(adapter, logger) {
    logger.i("Settings", "Migrating settings to v26");

    // Replace old calendar-card and banner-card with calendar-header-card and calendar-month-card
    if (adapter.calendar !== undefined && adapter.calendar.cards !== undefined) {
      const oldCards = adapter.calendar.cards;
      const newCards = [];
      let anyCalendarEnabled = false;

      // Check if any calendar-related card was enabled
      for (var i = 0; i < oldCards.length; i++) {
        const card = oldCards[i];
        if ((card.id === "banner-card" || card.id === "calendar-card") && card.enabled) {
          anyCalendarEnabled = true;
        } else if (card.id !== "banner-card" && card.id !== "calendar-card" && card.id !== 'calendar-month-card' && card.id !== 'calendar-header-card') {
          // Keep other cards as-is (timer, weather)
          newCards.push(card);
        }
      }

      // Add new split cards at the beginning (enabled if any old calendar card was enabled)
      newCards.unshift({
                         "id": "calendar-month-card",
                         "enabled": anyCalendarEnabled
                       });
      newCards.unshift({
                         "id": "calendar-header-card",
                         "enabled": anyCalendarEnabled
                       });

      adapter.calendar.cards = newCards;
      logger.i("Settings", "Replaced old calendar cards with calendar-header-card + calendar-month-card");
    }

    return true;
  }
}
