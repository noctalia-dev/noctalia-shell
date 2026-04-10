/*
 * Copyright 2022 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#ifndef CPP_CAM_VIEWING_CONDITIONS_H_
#define CPP_CAM_VIEWING_CONDITIONS_H_

namespace material_color_utilities {

struct ViewingConditions {
  double adapting_luminance = 0.0;
  double background_lstar = 0.0;
  double surround = 0.0;
  bool discounting_illuminant = false;
  double background_y_to_white_point_y = 0.0;
  double aw = 0.0;
  double nbb = 0.0;
  double ncb = 0.0;
  double c = 0.0;
  double n_c = 0.0;
  double fl = 0.0;
  double fl_root = 0.0;
  double z = 0.0;

  double white_point[3] = {0.0, 0.0, 0.0};
  double rgb_d[3] = {0.0, 0.0, 0.0};
};

ViewingConditions CreateViewingConditions(const double white_point[3],
                                          const double adapting_luminance,
                                          const double background_lstar,
                                          const double surround,
                                          const bool discounting_illuminant);

ViewingConditions DefaultWithBackgroundLstar(const double background_lstar);

static const ViewingConditions kDefaultViewingConditions = (ViewingConditions){
    11.725676537,
    50.000000000,
    2.000000000,
    false,
    0.184186503,
    29.981000900,
    1.016919255,
    1.016919255,
    0.689999998,
    1.000000000,
    0.388481468,
    0.789482653,
    1.909169555,
    {95.047, 100.0, 108.883},
    {1.021177769, 0.986307740, 0.933960497},
};

}  // namespace material_color_utilities
#endif  // CPP_CAM_VIEWING_CONDITIONS_H_
