#pragma once

#include "core/files/directory_scanner.h"
#include "ui/dialogs/file_dialog.h"

#include <cstddef>
#include <filesystem>
#include <memory>
#include <vector>

class AnimationManager;
class Button;
class Flex;
class Input;
class InputArea;
class Label;
class Node;
class Renderer;
class ScrollView;
class ThumbnailService;

class FileDialogHost {
public:
  virtual ~FileDialogHost() = default;

  virtual void requestUpdateOnly() = 0;
  virtual void requestLayout() = 0;
  virtual void requestRedraw() = 0;
  virtual void focusArea(InputArea* area) = 0;
  [[nodiscard]] virtual InputArea* focusedArea() const = 0;
  virtual void accept(std::optional<std::filesystem::path> result) = 0;
  virtual void cancel() = 0;
};

class FileDialogView {
public:
  explicit FileDialogView(ThumbnailService* thumbnails);
  ~FileDialogView();

  void setHost(FileDialogHost* host) noexcept { m_host = host; }
  void setAnimationManager(AnimationManager* animations) noexcept { m_animations = animations; }
  void setContentScale(float scale) noexcept { m_contentScale = scale; }

  [[nodiscard]] float contentScale() const noexcept { return m_contentScale; }
  [[nodiscard]] bool hasDecoration() const noexcept { return true; }
  [[nodiscard]] Node* root() const noexcept { return m_root ? m_root.get() : m_rootPtr; }

  void create();
  void onOpen(std::string_view context);
  void onClose();
  void layout(Renderer& renderer, float width, float height) { doLayout(renderer, width, height); }
  void update(Renderer& renderer) { doUpdate(renderer); }
  [[nodiscard]] std::unique_ptr<Node> releaseRoot() {
    m_rootPtr = m_root.get();
    return std::move(m_root);
  }
  [[nodiscard]] bool handleGlobalKey(std::uint32_t sym, std::uint32_t modifiers, bool pressed, bool preedit);

  [[nodiscard]] float preferredWidth() const { return scaled(800.0f); }
  [[nodiscard]] float preferredHeight() const { return scaled(560.0f); }
  [[nodiscard]] InputArea* initialFocusArea() const;

private:
  enum class ViewMode : std::uint8_t {
    List,
    Grid,
  };

  [[nodiscard]] float scaled(float value) const noexcept { return value * m_contentScale; }
  void setRoot(std::unique_ptr<Node> root) { m_root = std::move(root); }
  void clearReleasedRoot() noexcept { m_rootPtr = nullptr; }

  void doLayout(Renderer& renderer, float width, float height);
  void doUpdate(Renderer& renderer);

  void refreshDirectory();
  void applyFilter(bool resetScroll);
  void rebuildBreadcrumb();
  void rebuildVisibleEntries(Renderer& renderer);
  void rebuildList(Renderer& renderer, float width);
  void rebuildGrid(Renderer& renderer, float width);
  void ensureRowPool(float viewportHeight);
  void ensureTilePool(float viewportHeight, std::size_t columns);
  void refreshVisibleTileThumbnails(Renderer& renderer);
  void updateVisibleStates();
  void updateControls();
  void updateFilenameFieldFromSelection();
  void setShowHiddenFiles(bool show);
  void setViewMode(ViewMode mode);
  void setSort(FileDialogSortField field);
  void navigateInto(const std::filesystem::path& path);
  void navigateUp();
  void navigateHome();
  void selectIndex(std::size_t index);
  void handleEntryClick(std::size_t index);
  void activateSelection();
  void submitDialog();
  void focusSearch();
  void focusList();
  void focusFilename();
  void cycleFocus(bool reverse);
  void ensureSelectionVisible();
  [[nodiscard]] std::size_t firstSelectableIndex() const;
  [[nodiscard]] bool isSelectableIndex(std::size_t index) const;
  [[nodiscard]] bool isTextInputFocused() const;
  [[nodiscard]] std::filesystem::path selectedPath() const;
  [[nodiscard]] std::filesystem::path homeDirectory() const;
  [[nodiscard]] std::filesystem::path resolveStartDirectory(const std::filesystem::path& preferred) const;
  void requestUpdateOnly();
  void requestLayout();
  void requestRedraw();
  void focusHostArea(InputArea* area);
  [[nodiscard]] InputArea* hostFocusedArea() const;
  void acceptDialog(std::optional<std::filesystem::path> result);
  void cancelDialog();

  ThumbnailService* m_thumbnails = nullptr;
  FileDialogHost* m_host = nullptr;
  DirectoryScanner m_scanner;
  FileDialogOptions m_options;

  Flex* m_rootLayout = nullptr;
  Label* m_titleLabel = nullptr;
  Flex* m_breadcrumbRow = nullptr;
  Button* m_homeButton = nullptr;
  Button* m_backButton = nullptr;
  Input* m_searchInput = nullptr;
  Label* m_sortLabel = nullptr;
  Button* m_hiddenToggle = nullptr;
  Button* m_listToggle = nullptr;
  Button* m_gridToggle = nullptr;
  Flex* m_listContainer = nullptr;
  Button* m_nameSortButton = nullptr;
  Button* m_sizeSortButton = nullptr;
  Button* m_dateSortButton = nullptr;
  ScrollView* m_listScrollView = nullptr;
  Node* m_listRoot = nullptr;
  Label* m_listEmptyLabel = nullptr;
  ScrollView* m_gridScrollView = nullptr;
  Node* m_gridRoot = nullptr;
  Label* m_gridEmptyLabel = nullptr;
  Input* m_filenameInput = nullptr;
  Button* m_cancelButton = nullptr;
  Button* m_okButton = nullptr;
  InputArea* m_listFocusArea = nullptr;

  std::vector<FileEntry> m_entries;
  std::vector<FileEntry> m_visibleEntries;
  std::vector<InputArea*> m_rowPool;
  std::vector<InputArea*> m_tilePool;

  std::filesystem::path m_currentDirectory;
  std::string m_filterQuery;
  ViewMode m_viewMode = ViewMode::List;
  FileDialogSortField m_sortField = FileDialogSortField::Name;
  FileDialogSortOrder m_sortOrder = FileDialogSortOrder::Ascending;
  std::size_t m_selectedIndex = static_cast<std::size_t>(-1);
  std::size_t m_hoverIndex = static_cast<std::size_t>(-1);
  std::size_t m_rowPoolStartIndex = static_cast<std::size_t>(-1);
  std::size_t m_tilePoolStartIndex = static_cast<std::size_t>(-1);
  std::size_t m_gridColumns = 1;
  float m_lastWidth = 0.0f;
  float m_lastListWidth = -1.0f;
  float m_lastGridWidth = -1.0f;
  float m_listRowHeight = 0.0f;
  float m_gridCellWidth = 0.0f;
  float m_gridCellHeight = 0.0f;
  bool m_dirty = false;
  bool m_mouseActive = false;
  bool m_thumbnailRefreshPending = false;
  bool m_showHiddenFiles = false;
  float m_contentScale = 1.0f;
  AnimationManager* m_animations = nullptr;
  std::unique_ptr<Node> m_root;
  Node* m_rootPtr = nullptr;
};
