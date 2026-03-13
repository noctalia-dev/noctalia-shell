function selectNext(selectedIndex, resultsLength) {
  if (resultsLength > 0 && selectedIndex < resultsLength - 1)
    return selectedIndex + 1;
  return selectedIndex;
}

function selectPrevious(selectedIndex, resultsLength) {
  if (resultsLength > 0 && selectedIndex > 0)
    return selectedIndex - 1;
  return selectedIndex;
}

function selectNextWrapped(selectedIndex, resultsLength, allowWrap) {
  if (resultsLength > 0) {
    if (allowWrap)
      return (selectedIndex + 1) % resultsLength;
    return selectNext(selectedIndex, resultsLength);
  }
  return selectedIndex;
}

function selectPreviousWrapped(selectedIndex, resultsLength, allowWrap) {
  if (resultsLength > 0) {
    if (allowWrap)
      return (((selectedIndex - 1) % resultsLength) + resultsLength) % resultsLength;
    return selectPrevious(selectedIndex, resultsLength);
  }
  return selectedIndex;
}

function selectFirst() {
  return 0;
}

function selectLast(resultsLength) {
  return resultsLength > 0 ? resultsLength - 1 : 0;
}

function selectNextPage(selectedIndex, resultsLength, entryHeight) {
  if (resultsLength > 0) {
    var page = Math.max(1, Math.floor(600 / entryHeight));
    return Math.min(selectedIndex + page, resultsLength - 1);
  }
  return selectedIndex;
}

function selectPreviousPage(selectedIndex, resultsLength, entryHeight) {
  if (resultsLength > 0) {
    var page = Math.max(1, Math.floor(600 / entryHeight));
    return Math.max(selectedIndex - page, 0);
  }
  return selectedIndex;
}

function selectPreviousRow(selectedIndex, resultsLength, gridColumns) {
  if (resultsLength <= 0 || gridColumns <= 0)
    return selectedIndex;

  var currentRow = Math.floor(selectedIndex / gridColumns);
  var currentCol = selectedIndex % gridColumns;

  if (currentRow > 0) {
    var targetRow = currentRow - 1;
    var itemsInTargetRow = Math.min(gridColumns, resultsLength - targetRow * gridColumns);
    if (currentCol < itemsInTargetRow)
      return targetRow * gridColumns + currentCol;
    return targetRow * gridColumns + itemsInTargetRow - 1;
  }

  // Wrap to last row, same column
  var totalRows = Math.ceil(resultsLength / gridColumns);
  var lastRow = totalRows - 1;
  var itemsInLastRow = Math.min(gridColumns, resultsLength - lastRow * gridColumns);
  if (currentCol < itemsInLastRow)
    return lastRow * gridColumns + currentCol;
  return resultsLength - 1;
}

function selectNextRow(selectedIndex, resultsLength, gridColumns) {
  if (resultsLength <= 0 || gridColumns <= 0)
    return selectedIndex;

  var currentRow = Math.floor(selectedIndex / gridColumns);
  var currentCol = selectedIndex % gridColumns;
  var totalRows = Math.ceil(resultsLength / gridColumns);

  if (currentRow < totalRows - 1) {
    var targetRow = currentRow + 1;
    var targetIndex = targetRow * gridColumns + currentCol;
    if (targetIndex < resultsLength)
      return targetIndex;
    var itemsInTargetRow = resultsLength - targetRow * gridColumns;
    if (itemsInTargetRow > 0)
      return targetRow * gridColumns + itemsInTargetRow - 1;
    return Math.min(currentCol, resultsLength - 1);
  }

  // Wrap to first row, same column
  return Math.min(currentCol, resultsLength - 1);
}

function selectPreviousColumn(selectedIndex, resultsLength, gridColumns) {
  if (resultsLength <= 0)
    return selectedIndex;

  var currentRow = Math.floor(selectedIndex / gridColumns);
  var currentCol = selectedIndex % gridColumns;

  if (currentCol > 0)
    return currentRow * gridColumns + (currentCol - 1);
  if (currentRow > 0)
    return (currentRow - 1) * gridColumns + (gridColumns - 1);

  var totalRows = Math.ceil(resultsLength / gridColumns);
  var lastRowIndex = (totalRows - 1) * gridColumns + (gridColumns - 1);
  return Math.min(lastRowIndex, resultsLength - 1);
}

function selectNextColumn(selectedIndex, resultsLength, gridColumns) {
  if (resultsLength <= 0)
    return selectedIndex;

  var currentRow = Math.floor(selectedIndex / gridColumns);
  var currentCol = selectedIndex % gridColumns;
  var itemsInCurrentRow = Math.min(gridColumns, resultsLength - currentRow * gridColumns);

  if (currentCol < itemsInCurrentRow - 1)
    return currentRow * gridColumns + (currentCol + 1);

  var totalRows = Math.ceil(resultsLength / gridColumns);
  if (currentRow < totalRows - 1)
    return (currentRow + 1) * gridColumns;
  return 0;
}
