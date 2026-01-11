pragma Singleton

import QtQuick
import Quickshell

Singleton {
  id: root

  // Public API
  function go(search, targets, options) {
    return _go(search, targets, options);
  }

  function single(search, target) {
    return _single(search, target);
  }

  function highlight(result, open, close) {
    if (open === undefined)
      open = '<b>';
    if (close === undefined)
      close = '</b>';
    return _highlight(result, open, close);
  }

  function prepare(target) {
    return _prepare(target);
  }

  function cleanup() {
    return _cleanup();
  }

  // Internal implementation
  readonly property var _INFINITY: Infinity
  readonly property var _NEGATIVE_INFINITY: -Infinity
  readonly property var _NULL: null
  property var _noResults: {
    let r = [];
    r.total = 0;
    return r;
  }
  property var _noTarget: _prepare('')

  property var _preparedCache: new Map()
  property var _preparedSearchCache: new Map()

  property var _matchesSimple: []
  property var _matchesStrict: []
  property var _nextBeginningIndexesChanges: []
  property var _keysSpacesBestScores: []
  property var _allowPartialMatchScores: []
  property var _tmpTargets: []
  property var _tmpResults: []
  property var _q: _fastpriorityqueue()

  function _fastpriorityqueue() {
    var e = [], o = 0, a = {};
    var v = function (r) {
      for (var a = 0, vc = e[a], c = 1; c < o; ) {
        var s = c + 1;
        a = c;
        if (s < o && e[s]._score < e[c]._score)
          a = s;
        e[a - 1 >> 1] = e[a];
        c = 1 + (a << 1);
      }
      for (var f = a - 1 >> 1; a > 0 && vc._score < e[f]._score; f = (a = f) - 1 >> 1)
        e[a] = e[f];
      e[a] = vc;
    };
    a.add = function (r) {
      var ac = o;
      e[o++] = r;
      for (var vc = ac - 1 >> 1; ac > 0 && r._score < e[vc]._score; vc = (ac = vc) - 1 >> 1)
        e[ac] = e[vc];
      e[ac] = r;
    };
    a.poll = function () {
      if (o !== 0) {
        var ac = e[0];
        e[0] = e[--o];
        v();
        return ac;
      }
    };
    a.peek = function () {
      if (o !== 0)
        return e[0];
    };
    a.replaceTop = function (r) {
      e[0] = r;
      v();
    };
    return a;
  }

  function _createResult() {
    return {
      target: '',
      obj: _NULL,
      _score: _NEGATIVE_INFINITY,
      _indexes: [],
      _targetLower: '',
      _targetLowerCodes: _NULL,
      _nextBeginningIndexes: _NULL,
      _bitflags: 0,
      get indexes() {
        return this._indexes.slice(0, this._indexes.len).sort((a, b) => a - b);
      },
      set indexes(idx) {
        this._indexes = idx;
      },
      highlight: function (open, close) {
        return root._highlight(this, open, close);
      },
      get score() {
        return root._normalizeScore(this._score);
      },
      set score(s) {
        this._score = root._denormalizeScore(s);
      }
    };
  }

  function _createKeysResult(len) {
    var arr = new Array(len);
    arr._score = _NEGATIVE_INFINITY;
    arr.obj = _NULL;
    Object.defineProperty(arr, 'score', {
                            get: function () {
                              return root._normalizeScore(this._score);
                            },
                            set: function (s) {
                              this._score = root._denormalizeScore(s);
                            }
                          });
    return arr;
  }

  function _new_result(target, options) {
    var result = _createResult();
    result.target = target;
    result.obj = options.obj ?? _NULL;
    result._score = options._score ?? _NEGATIVE_INFINITY;
    result._indexes = options._indexes ?? [];
    result._targetLower = options._targetLower ?? '';
    result._targetLowerCodes = options._targetLowerCodes ?? _NULL;
    result._nextBeginningIndexes = options._nextBeginningIndexes ?? _NULL;
    result._bitflags = options._bitflags ?? 0;
    return result;
  }

  function _normalizeScore(score) {
    if (score === _NEGATIVE_INFINITY)
      return 0;
    if (score > 1)
      return score;
    return Math.E ** (((-score + 1) ** 0.04307 - 1) * -2);
  }

  function _denormalizeScore(normalizedScore) {
    if (normalizedScore === 0)
      return _NEGATIVE_INFINITY;
    if (normalizedScore > 1)
      return normalizedScore;
    return 1 - Math.pow((Math.log(normalizedScore) / -2 + 1), 1 / 0.04307);
  }

  function _remove_accents(str) {
    return str.replace(/\p{Script=Latin}+/gu, match => match.normalize('NFD')).replace(/[\u0300-\u036f]/g, '');
  }

  function _prepareLowerInfo(str) {
    str = _remove_accents(str);
    var strLen = str.length;
    var lower = str.toLowerCase();
    var lowerCodes = [];
    var bitflags = 0;
    var containsSpace = false;

    for (var i = 0; i < strLen; ++i) {
      var lowerCode = lowerCodes[i] = lower.charCodeAt(i);
      if (lowerCode === 32) {
        containsSpace = true;
        continue;
      }
      var bit = lowerCode >= 97 && lowerCode <= 122 ? lowerCode - 97 : lowerCode >= 48 && lowerCode <= 57 ? 26 : lowerCode <= 127 ? 30 : 31;
      bitflags |= 1 << bit;
    }
    return {
      lowerCodes: lowerCodes,
      bitflags: bitflags,
      containsSpace: containsSpace,
      _lower: lower
    };
  }

  function _prepareBeginningIndexes(target) {
    var targetLen = target.length;
    var beginningIndexes = [];
    var beginningIndexesLen = 0;
    var wasUpper = false;
    var wasAlphanum = false;
    for (var i = 0; i < targetLen; ++i) {
      var targetCode = target.charCodeAt(i);
      var isUpper = targetCode >= 65 && targetCode <= 90;
      var isAlphanum = isUpper || targetCode >= 97 && targetCode <= 122 || targetCode >= 48 && targetCode <= 57;
      var isBeginning = isUpper && !wasUpper || !wasAlphanum || !isAlphanum;
      wasUpper = isUpper;
      wasAlphanum = isAlphanum;
      if (isBeginning)
        beginningIndexes[beginningIndexesLen++] = i;
    }
    return beginningIndexes;
  }

  function _prepareNextBeginningIndexes(target) {
    target = _remove_accents(target);
    var targetLen = target.length;
    var beginningIndexes = _prepareBeginningIndexes(target);
    var nextBeginningIndexes = [];
    var lastIsBeginning = beginningIndexes[0];
    var lastIsBeginningI = 0;
    for (var i = 0; i < targetLen; ++i) {
      if (lastIsBeginning > i) {
        nextBeginningIndexes[i] = lastIsBeginning;
      } else {
        lastIsBeginning = beginningIndexes[++lastIsBeginningI];
        nextBeginningIndexes[i] = lastIsBeginning === undefined ? targetLen : lastIsBeginning;
      }
    }
    return nextBeginningIndexes;
  }

  function _prepareSearch(search) {
    if (typeof search === 'number')
      search = '' + search;
    else if (typeof search !== 'string')
      search = '';
    search = search.trim();
    var info = _prepareLowerInfo(search);

    var spaceSearches = [];
    if (info.containsSpace) {
      var searches = search.split(/\s+/);
      searches = [...new Set(searches)];
      for (var i = 0; i < searches.length; i++) {
        if (searches[i] === '')
          continue;
        var _info = _prepareLowerInfo(searches[i]);
        spaceSearches.push({
                             lowerCodes: _info.lowerCodes,
                             _lower: searches[i].toLowerCase(),
                             containsSpace: false
                           });
      }
    }
    return {
      lowerCodes: info.lowerCodes,
      _lower: info._lower,
      containsSpace: info.containsSpace,
      bitflags: info.bitflags,
      spaceSearches: spaceSearches
    };
  }

  function _prepare(target) {
    if (typeof target === 'number')
      target = '' + target;
    else if (typeof target !== 'string')
      target = '';
    var info = _prepareLowerInfo(target);
    return _new_result(target, {
                         _targetLower: info._lower,
                         _targetLowerCodes: info.lowerCodes,
                         _bitflags: info.bitflags
                       });
  }

  function _cleanup() {
    _preparedCache.clear();
    _preparedSearchCache.clear();
  }

  function _isPrepared(x) {
    return typeof x === 'object' && typeof x._bitflags === 'number';
  }

  function _getPrepared(target) {
    if (target.length > 999)
      return _prepare(target);
    var targetPrepared = _preparedCache.get(target);
    if (targetPrepared !== undefined)
      return targetPrepared;
    targetPrepared = _prepare(target);
    _preparedCache.set(target, targetPrepared);
    return targetPrepared;
  }

  function _getPreparedSearch(search) {
    if (search.length > 999)
      return _prepareSearch(search);
    var searchPrepared = _preparedSearchCache.get(search);
    if (searchPrepared !== undefined)
      return searchPrepared;
    searchPrepared = _prepareSearch(search);
    _preparedSearchCache.set(search, searchPrepared);
    return searchPrepared;
  }

  function _getValue(obj, prop) {
    var tmp = obj[prop];
    if (tmp !== undefined)
      return tmp;
    if (typeof prop === 'function')
      return prop(obj);
    var segs = prop;
    if (!Array.isArray(prop))
      segs = prop.split('.');
    var len = segs.length;
    var i = -1;
    while (obj && (++i < len))
      obj = obj[segs[i]];
    return obj;
  }

  function _single(search, target) {
    if (!search || !target)
      return _NULL;
    var preparedSearch = _getPreparedSearch(search);
    if (!_isPrepared(target))
      target = _getPrepared(target);
    var searchBitflags = preparedSearch.bitflags;
    if ((searchBitflags & target._bitflags) !== searchBitflags)
      return _NULL;
    return _algorithm(preparedSearch, target);
  }

  function _highlight(result, open, close) {
    if (open === undefined)
      open = '<b>';
    if (close === undefined)
      close = '</b>';
    var callback = typeof open === 'function' ? open : undefined;

    var target = result.target;
    var targetLen = target.length;
    var indexes = result.indexes;
    var highlighted = '';
    var matchI = 0;
    var indexesI = 0;
    var opened = false;
    var parts = [];

    for (var i = 0; i < targetLen; ++i) {
      var ch = target[i];
      if (indexes[indexesI] === i) {
        ++indexesI;
        if (!opened) {
          opened = true;
          if (callback) {
            parts.push(highlighted);
            highlighted = '';
          } else {
            highlighted += open;
          }
        }
        if (indexesI === indexes.length) {
          if (callback) {
            highlighted += ch;
            parts.push(callback(highlighted, matchI++));
            highlighted = '';
            parts.push(target.substr(i + 1));
          } else {
            highlighted += ch + close + target.substr(i + 1);
          }
          break;
        }
      } else {
        if (opened) {
          opened = false;
          if (callback) {
            parts.push(callback(highlighted, matchI++));
            highlighted = '';
          } else {
            highlighted += close;
          }
        }
      }
      highlighted += ch;
    }
    return callback ? parts : highlighted;
  }

  function _all(targets, options) {
    var results = [];
    results.total = targets.length;
    var limit = options?.limit || _INFINITY;

    if (options?.key) {
      for (var i = 0; i < targets.length; i++) {
        var obj = targets[i];
        var target = _getValue(obj, options.key);
        if (target == _NULL)
          continue;
        if (!_isPrepared(target))
          target = _getPrepared(target);
        var result = _new_result(target.target, {
                                   _score: target._score,
                                   obj: obj
                                 });
        results.push(result);
        if (results.length >= limit)
          return results;
      }
    } else if (options?.keys) {
      for (var i = 0; i < targets.length; i++) {
        var obj = targets[i];
        var objResults = _createKeysResult(options.keys.length);
        for (var keyI = options.keys.length - 1; keyI >= 0; --keyI) {
          var target = _getValue(obj, options.keys[keyI]);
          if (!target) {
            objResults[keyI] = _noTarget;
            continue;
          }
          if (!_isPrepared(target))
            target = _getPrepared(target);
          target._score = _NEGATIVE_INFINITY;
          target._indexes.len = 0;
          objResults[keyI] = target;
        }
        objResults.obj = obj;
        objResults._score = _NEGATIVE_INFINITY;
        results.push(objResults);
        if (results.length >= limit)
          return results;
      }
    } else {
      for (var i = 0; i < targets.length; i++) {
        var target = targets[i];
        if (target == _NULL)
          continue;
        if (!_isPrepared(target))
          target = _getPrepared(target);
        target._score = _NEGATIVE_INFINITY;
        target._indexes.len = 0;
        results.push(target);
        if (results.length >= limit)
          return results;
      }
    }
    return results;
  }

  function _algorithm(preparedSearch, prepared, allowSpaces, allowPartialMatch) {
    if (allowSpaces === undefined)
      allowSpaces = false;
    if (allowPartialMatch === undefined)
      allowPartialMatch = false;

    if (allowSpaces === false && preparedSearch.containsSpace)
      return _algorithmSpaces(preparedSearch, prepared, allowPartialMatch);

    var searchLower = preparedSearch._lower;
    var searchLowerCodes = preparedSearch.lowerCodes;
    var searchLowerCode = searchLowerCodes[0];
    var targetLowerCodes = prepared._targetLowerCodes;
    var searchLen = searchLowerCodes.length;
    var targetLen = targetLowerCodes.length;
    var searchI = 0;
    var targetI = 0;
    var matchesSimpleLen = 0;

    for (; ; ) {
      var isMatch = searchLowerCode === targetLowerCodes[targetI];
      if (isMatch) {
        _matchesSimple[matchesSimpleLen++] = targetI;
        ++searchI;
        if (searchI === searchLen)
          break;
        searchLowerCode = searchLowerCodes[searchI];
      }
      ++targetI;
      if (targetI >= targetLen)
        return _NULL;
    }

    searchI = 0;
    var successStrict = false;
    var matchesStrictLen = 0;

    var nextBeginningIndexes = prepared._nextBeginningIndexes;
    if (nextBeginningIndexes === _NULL)
      nextBeginningIndexes = prepared._nextBeginningIndexes = _prepareNextBeginningIndexes(prepared.target);
    targetI = _matchesSimple[0] === 0 ? 0 : nextBeginningIndexes[_matchesSimple[0] - 1];

    var backtrackCount = 0;
    if (targetI !== targetLen)
      for (; ; ) {
        if (targetI >= targetLen) {
          if (searchI <= 0)
            break;
          ++backtrackCount;
          if (backtrackCount > 200)
            break;
          --searchI;
          var lastMatch = _matchesStrict[--matchesStrictLen];
          targetI = nextBeginningIndexes[lastMatch];
        } else {
          var isMatch = searchLowerCodes[searchI] === targetLowerCodes[targetI];
          if (isMatch) {
            _matchesStrict[matchesStrictLen++] = targetI;
            ++searchI;
            if (searchI === searchLen) {
              successStrict = true;
              break;
            }
            ++targetI;
          } else {
            targetI = nextBeginningIndexes[targetI];
          }
        }
      }

    var substringIndex = searchLen <= 1 ? -1 : prepared._targetLower.indexOf(searchLower, _matchesSimple[0]);
    var isSubstring = !!~substringIndex;
    var isSubstringBeginning = !isSubstring ? false : substringIndex === 0 || prepared._nextBeginningIndexes[substringIndex - 1] === substringIndex;

    if (isSubstring && !isSubstringBeginning) {
      for (var i = 0; i < nextBeginningIndexes.length; i = nextBeginningIndexes[i]) {
        if (i <= substringIndex)
          continue;
        for (var s = 0; s < searchLen; s++)
          if (searchLowerCodes[s] !== prepared._targetLowerCodes[i + s])
            break;
        if (s === searchLen) {
          substringIndex = i;
          isSubstringBeginning = true;
          break;
        }
      }
    }

    var calculateScore = function (matches) {
      var score = 0;
      var extraMatchGroupCount = 0;
      for (var i = 1; i < searchLen; ++i) {
        if (matches[i] - matches[i - 1] !== 1) {
          score -= matches[i];
          ++extraMatchGroupCount;
        }
      }
      var unmatchedDistance = matches[searchLen - 1] - matches[0] - (searchLen - 1);
      score -= (12 + unmatchedDistance) * extraMatchGroupCount;
      if (matches[0] !== 0)
        score -= matches[0] * matches[0] * 0.2;
      if (!successStrict) {
        score *= 1000;
      } else {
        var uniqueBeginningIndexes = 1;
        for (var i = nextBeginningIndexes[0]; i < targetLen; i = nextBeginningIndexes[i])
          ++uniqueBeginningIndexes;
        if (uniqueBeginningIndexes > 24)
          score *= (uniqueBeginningIndexes - 24) * 10;
      }
      score -= (targetLen - searchLen) / 2;
      if (isSubstring)
        score /= 1 + searchLen * searchLen * 1;
      if (isSubstringBeginning)
        score /= 1 + searchLen * searchLen * 1;
      score -= (targetLen - searchLen) / 2;
      return score;
    };

    var matchesBest, score;
    if (!successStrict) {
      if (isSubstring)
        for (var i = 0; i < searchLen; ++i)
          _matchesSimple[i] = substringIndex + i;
      matchesBest = _matchesSimple;
      score = calculateScore(matchesBest);
    } else {
      if (isSubstringBeginning) {
        for (var i = 0; i < searchLen; ++i)
          _matchesSimple[i] = substringIndex + i;
        matchesBest = _matchesSimple;
        score = calculateScore(_matchesSimple);
      } else {
        matchesBest = _matchesStrict;
        score = calculateScore(_matchesStrict);
      }
    }

    prepared._score = score;
    for (var i = 0; i < searchLen; ++i)
      prepared._indexes[i] = matchesBest[i];
    prepared._indexes.len = searchLen;

    var result = _createResult();
    result.target = prepared.target;
    result._score = prepared._score;
    result._indexes = prepared._indexes;
    return result;
  }

  function _algorithmSpaces(preparedSearch, target, allowPartialMatch) {
    var seen_indexes = new Set();
    var score = 0;
    var result = _NULL;

    var first_seen_index_last_search = 0;
    var searches = preparedSearch.spaceSearches;
    var searchesLen = searches.length;
    var changeslen = 0;

    var resetNextBeginningIndexes = function () {
      for (let i = changeslen - 1; i >= 0; i--)
        target._nextBeginningIndexes[_nextBeginningIndexesChanges[i * 2 + 0]] = _nextBeginningIndexesChanges[i * 2 + 1];
    };

    var hasAtLeast1Match = false;
    for (var i = 0; i < searchesLen; ++i) {
      _allowPartialMatchScores[i] = _NEGATIVE_INFINITY;
      var search = searches[i];
      result = _algorithm(search, target);

      if (allowPartialMatch) {
        if (result === _NULL)
          continue;
        hasAtLeast1Match = true;
      } else {
        if (result === _NULL) {
          resetNextBeginningIndexes();
          return _NULL;
        }
      }

      var isTheLastSearch = i === searchesLen - 1;
      if (!isTheLastSearch) {
        var indexes = result._indexes;
        var indexesIsConsecutiveSubstring = true;
        for (let j = 0; j < indexes.len - 1; j++) {
          if (indexes[j + 1] - indexes[j] !== 1) {
            indexesIsConsecutiveSubstring = false;
            break;
          }
        }

        if (indexesIsConsecutiveSubstring) {
          var newBeginningIndex = indexes[indexes.len - 1] + 1;
          var toReplace = target._nextBeginningIndexes[newBeginningIndex - 1];
          for (let j = newBeginningIndex - 1; j >= 0; j--) {
            if (toReplace !== target._nextBeginningIndexes[j])
              break;
            target._nextBeginningIndexes[j] = newBeginningIndex;
            _nextBeginningIndexesChanges[changeslen * 2 + 0] = j;
            _nextBeginningIndexesChanges[changeslen * 2 + 1] = toReplace;
            changeslen++;
          }
        }
      }

      score += result._score / searchesLen;
      _allowPartialMatchScores[i] = result._score / searchesLen;

      if (result._indexes[0] < first_seen_index_last_search) {
        score -= (first_seen_index_last_search - result._indexes[0]) * 2;
      }
      first_seen_index_last_search = result._indexes[0];

      for (var j = 0; j < result._indexes.len; ++j)
        seen_indexes.add(result._indexes[j]);
    }

    if (allowPartialMatch && !hasAtLeast1Match)
      return _NULL;

    resetNextBeginningIndexes();

    var allowSpacesResult = _algorithm(preparedSearch, target, true);
    if (allowSpacesResult !== _NULL && allowSpacesResult._score > score) {
      if (allowPartialMatch) {
        for (var i = 0; i < searchesLen; ++i) {
          _allowPartialMatchScores[i] = allowSpacesResult._score / searchesLen;
        }
      }
      return allowSpacesResult;
    }

    if (allowPartialMatch)
      result = target;
    result._score = score;

    var idx = 0;
    for (let index of seen_indexes)
      result._indexes[idx++] = index;
    result._indexes.len = idx;

    return result;
  }

  function _go(search, targets, options) {
    if (!search)
      return options?.all ? _all(targets, options) : _noResults;

    var preparedSearch = _getPreparedSearch(search);
    var searchBitflags = preparedSearch.bitflags;
    var containsSpace = preparedSearch.containsSpace;

    var threshold = _denormalizeScore(options?.threshold || 0);
    var limit = options?.limit || _INFINITY;

    var resultsLen = 0;
    var limitedCount = 0;
    var targetsLen = targets.length;

    function push_result(result) {
      if (resultsLen < limit) {
        _q.add(result);
        ++resultsLen;
      } else {
        ++limitedCount;
        if (result._score > _q.peek()._score)
          _q.replaceTop(result);
      }
    }

    if (options?.key) {
      var key = options.key;
      for (var i = 0; i < targetsLen; ++i) {
        var obj = targets[i];
        var target = _getValue(obj, key);
        if (!target)
          continue;
        if (!_isPrepared(target))
          target = _getPrepared(target);
        if ((searchBitflags & target._bitflags) !== searchBitflags)
          continue;
        var result = _algorithm(preparedSearch, target);
        if (result === _NULL)
          continue;
        if (result._score < threshold)
          continue;
        result.obj = obj;
        push_result(result);
      }
    } else if (options?.keys) {
      var keys = options.keys;
      var keysLen = keys.length;

      outer: for (var i = 0; i < targetsLen; ++i) {
        var obj = targets[i];
        var keysBitflags = 0;
        for (var keyI = 0; keyI < keysLen; ++keyI) {
          var key = keys[keyI];
          var target = _getValue(obj, key);
          if (!target) {
            _tmpTargets[keyI] = _noTarget;
            continue;
          }
          if (!_isPrepared(target))
            target = _getPrepared(target);
          _tmpTargets[keyI] = target;
          keysBitflags |= target._bitflags;
        }

        if ((searchBitflags & keysBitflags) !== searchBitflags)
          continue;

        if (containsSpace)
          for (let j = 0; j < preparedSearch.spaceSearches.length; j++)
            _keysSpacesBestScores[j] = _NEGATIVE_INFINITY;

        for (var keyI = 0; keyI < keysLen; ++keyI) {
          target = _tmpTargets[keyI];
          if (target === _noTarget) {
            _tmpResults[keyI] = _noTarget;
            continue;
          }

          _tmpResults[keyI] = _algorithm(preparedSearch, target, false, containsSpace);
          if (_tmpResults[keyI] === _NULL) {
            _tmpResults[keyI] = _noTarget;
            continue;
          }

          if (containsSpace)
            for (let j = 0; j < preparedSearch.spaceSearches.length; j++) {
              if (_allowPartialMatchScores[j] > -1000) {
                if (_keysSpacesBestScores[j] > _NEGATIVE_INFINITY) {
                  var tmp = (_keysSpacesBestScores[j] + _allowPartialMatchScores[j]) / 4;
                  if (tmp > _keysSpacesBestScores[j])
                    _keysSpacesBestScores[j] = tmp;
                }
              }
              if (_allowPartialMatchScores[j] > _keysSpacesBestScores[j])
                _keysSpacesBestScores[j] = _allowPartialMatchScores[j];
            }
        }

        if (containsSpace) {
          for (let j = 0; j < preparedSearch.spaceSearches.length; j++)
            if (_keysSpacesBestScores[j] === _NEGATIVE_INFINITY)
              continue outer;
        } else {
          var hasAtLeast1Match = false;
          for (let j = 0; j < keysLen; j++)
            if (_tmpResults[j]._score !== _NEGATIVE_INFINITY) {
              hasAtLeast1Match = true;
              break;
            }
          if (!hasAtLeast1Match)
            continue;
        }

        var objResults = _createKeysResult(keysLen);
        for (let j = 0; j < keysLen; j++)
          objResults[j] = _tmpResults[j];

        var score;
        if (containsSpace) {
          score = 0;
          for (let j = 0; j < preparedSearch.spaceSearches.length; j++)
            score += _keysSpacesBestScores[j];
        } else {
          score = _NEGATIVE_INFINITY;
          for (let j = 0; j < keysLen; j++) {
            var res = objResults[j];
            if (res._score > -1000) {
              if (score > _NEGATIVE_INFINITY) {
                var tmp = (score + res._score) / 4;
                if (tmp > score)
                  score = tmp;
              }
            }
            if (res._score > score)
              score = res._score;
          }
        }

        objResults.obj = obj;
        objResults._score = score;

        if (options?.scoreFn) {
          score = options.scoreFn(objResults);
          if (!score)
            continue;
          score = _denormalizeScore(score);
          objResults._score = score;
        }

        if (score < threshold)
          continue;
        push_result(objResults);
      }
    } else {
      for (var i = 0; i < targetsLen; ++i) {
        var target = targets[i];
        if (!target)
          continue;
        if (!_isPrepared(target))
          target = _getPrepared(target);
        if ((searchBitflags & target._bitflags) !== searchBitflags)
          continue;
        var result = _algorithm(preparedSearch, target);
        if (result === _NULL)
          continue;
        if (result._score < threshold)
          continue;
        push_result(result);
      }
    }

    if (resultsLen === 0)
      return _noResults;
    var results = new Array(resultsLen);
    for (var i = resultsLen - 1; i >= 0; --i)
      results[i] = _q.poll();
    results.total = resultsLen + limitedCount;
    return results;
  }
}
