#pragma once

#include "config/config_types.h"

#include <chrono>
#include <optional>
#include <string_view>

namespace day_night_schedule {

  struct GeoCoordinates {
    std::optional<double> latitude;
    std::optional<double> longitude;
  };

  struct Evaluation {
    bool night = false;
    std::chrono::milliseconds untilBoundary = std::chrono::hours(1);
  };

  // resolvedLatitude/resolvedLongitude are the coordinates published by LocationService
  // (IP geolocation or geocoded address). When absent, manual latitude/longitude from the
  // config are used; fixed sunrise/sunset times are the final fallback.
  [[nodiscard]] std::optional<std::string> normalizedClock(std::string_view value);
  [[nodiscard]] GeoCoordinates resolveCoordinates(
      const LocationConfig& config, std::optional<double> resolvedLatitude, std::optional<double> resolvedLongitude
  );
  [[nodiscard]] bool isManualMode(
      const LocationConfig& config, std::optional<double> resolvedLatitude, std::optional<double> resolvedLongitude
  );
  [[nodiscard]] Evaluation evaluate(
      const LocationConfig& config, std::optional<double> resolvedLatitude, std::optional<double> resolvedLongitude
  );

} // namespace day_night_schedule
