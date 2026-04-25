#pragma once

class Box;
class Flex;
class ScrollView;

namespace ui {

  void applyCardStyle(Box& box, float scale = 1.0f);
  void applyCardStyle(Flex& flex, float scale = 1.0f);
  void applyCardStyle(ScrollView& scrollView, float scale = 1.0f);

} // namespace ui
