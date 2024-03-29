// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// Copyright (c) 2014, Google Inc. Please see the AUTHORS file for details.
// All rights reserved. Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

library pub_semver.src.version;

import 'dart:math';

import 'package:collection/equality.dart';

import 'patterns.dart';
import 'version_constraint.dart';
import 'version_range.dart';

/// The equality operator to use for comparing version components.
final _equality = const IterableEquality();

/// A parsed semantic version number.
class Version implements Comparable<Version>, VersionConstraint {
  /// Zero version to be used in comparisons.
  static final Version zero = new Version(0, 0, 0);
  /// Infinite "unreachable" version to be used in comparisons.
  /// TODO(ussuri): This is a little hacky.
  static final Version infinity = new Version(1000000000000, 0, 0);

  /// No released version: i.e. "0.0.0".
  static Version get none => new Version(0, 0, 0);

  /// Compares [a] and [b] to see which takes priority over the other.
  ///
  /// Returns `1` if [a] takes priority over [b] and `-1` if vice versa. If
  /// [a] and [b] are equivalent, returns `0`.
  ///
  /// Unlike [compareTo], which *orders* versions, this determines which
  /// version a user is likely to prefer. In particular, it prioritizes
  /// pre-release versions lower than stable versions, regardless of their
  /// version numbers. Pub uses this when determining which version to prefer
  /// when a number of versions are allowed. In that case, it will always
  /// choose a stable version when possible.
  ///
  /// When used to sort a list, orders in ascending priority so that the
  /// highest priority version is *last* in the result.
  static int prioritize(Version a, Version b) {
    // Sort all prerelease versions after all normal versions. This way
    // the solver will prefer stable packages over unstable ones.
    if (a.isPreRelease && !b.isPreRelease) return -1;
    if (!a.isPreRelease && b.isPreRelease) return 1;

    return a.compareTo(b);
  }

  /// Like [proiritize], but lower version numbers are considered greater than
  /// higher version numbers.
  ///
  /// This still considers prerelease versions to be lower than non-prerelease
  /// versions. Pub uses this when downgrading -- it chooses the lowest version
  /// but still excludes pre-release versions when possible.
  static int antiprioritize(Version a, Version b) {
    if (a.isPreRelease && !b.isPreRelease) return -1;
    if (!a.isPreRelease && b.isPreRelease) return 1;

    return b.compareTo(a);
  }

  /// The major version number: "1" in "1.2.3".
  final int major;

  /// The minor version number: "2" in "1.2.3".
  final int minor;

  /// The patch version number: "3" in "1.2.3".
  final int patch;

  /// The pre-release identifier: "foo" in "1.2.3-foo".
  ///
  /// This is split into a list of components, each of which may be either a
  /// string or a non-negative integer. It may also be empty, indicating that
  /// this version has no pre-release identifier.
  final List preRelease;

  /// The build identifier: "foo" in "1.2.3+foo".
  ///
  /// This is split into a list of components, each of which may be either a
  /// string or a non-negative integer. It may also be empty, indicating that
  /// this version has no build identifier.
  final List build;

  /// The original string representation of the version number.
  ///
  /// This preserves textual artifacts like leading zeros that may be left out
  /// of the parsed version.
  final String _text;

  Version._(this.major, this.minor, this.patch, String preRelease, String build,
            this._text)
      : preRelease = preRelease == null ? [] : _splitParts(preRelease),
        build = build == null ? [] : _splitParts(build) {
    if (major < 0) throw new ArgumentError(
        'Major version must be non-negative.');
    if (minor < 0) throw new ArgumentError(
        'Minor version must be non-negative.');
    if (patch < 0) throw new ArgumentError(
        'Patch version must be non-negative.');
  }

  /// Creates a new [Version] object.
  factory Version(int major, int minor, int patch, {String pre, String build}) {
    var text = "$major.$minor.$patch";
    if (pre != null) text += "-$pre";
    if (build != null) text += "+$build";

    return new Version._(major, minor, patch, pre, build, text);
  }

  /// Creates a new [Version] by parsing [text].
  factory Version.parse(String text) {
    final match = COMPLETE_VERSION.firstMatch(text);
    if (match == null) {
      throw new FormatException('Could not parse "$text".');
    }

    try {
      int major = int.parse(match[1]);
      int minor = int.parse(match[2]);
      int patch = int.parse(match[3]);

      String preRelease = match[5];
      String build = match[8];

      return new Version._(major, minor, patch, preRelease, build, text);
    } on FormatException catch (ex) {
      throw new FormatException('Could not parse "$text".');
    }
  }

  /// Returns the primary version out of a list of candidates.
  ///
  /// This is the highest-numbered stable (non-prerelease) version. If there
  /// are no stable versions, it's just the highest-numbered version.
  static Version primary(List<Version> versions) {
    var primary;
    for (var version in versions) {
      if (primary == null || (!version.isPreRelease && primary.isPreRelease) ||
          (version.isPreRelease == primary.isPreRelease && version > primary)) {
        primary = version;
      }
    }
    return primary;
  }

  /// Splits a string of dot-delimited identifiers into their component parts.
  ///
  /// Identifiers that are numeric are converted to numbers.
  static List _splitParts(String text) {
    return text.split('.').map((part) {
      try {
        return int.parse(part);
      } on FormatException catch (ex) {
        // Not a number.
        return part;
      }
    }).toList();
  }

  // TODO(ussuri): Right now [_isX] will always return false by construction.
  // Add support for X's as version parts in [Version] and/or [VersionRange].
  static const _xs = const [null, 'x', 'X', '*'];
  bool _isX(var versionPart) => _xs.contains(versionPart);

  bool operator ==(other) {
    if (other is! Version) return false;
    return major == other.major && minor == other.minor &&
        patch == other.patch &&
        _equality.equals(preRelease, other.preRelease) &&
        _equality.equals(build, other.build);
  }

  int get hashCode => major ^ minor ^ patch ^ _equality.hash(preRelease) ^
      _equality.hash(build);

  bool operator <(Version other) => compareTo(other) < 0;
  bool operator >(Version other) => compareTo(other) > 0;
  bool operator <=(Version other) => compareTo(other) <= 0;
  bool operator >=(Version other) => compareTo(other) >= 0;

  bool get isAny => false;
  bool get isEmpty => false;

  /// Whether or not this is a pre-release version.
  bool get isPreRelease => preRelease.isNotEmpty;

  /// Gets the next major version number that follows this one.
  ///
  /// If this version is a pre-release of a major version release (i.e. the
  /// minor and patch versions are zero), then it just strips the pre-release
  /// suffix. Otherwise, it increments the major version and resets the minor
  /// and patch.
  Version get nextMajor {
    if (isPreRelease && minor == 0 && patch == 0) {
      return new Version(major, minor, patch);
    }

    return new Version(major + 1, 0, 0);
  }

  /// Gets the next minor version number that follows this one.
  ///
  /// If this version is a pre-release of a minor version release (i.e. the
  /// patch version is zero), then it just strips the pre-release suffix.
  /// Otherwise, it increments the minor version and resets the patch.
  Version get nextMinor {
    if (isPreRelease && patch == 0) {
      return new Version(major, minor, patch);
    }

    return new Version(major, minor + 1, 0);
  }

  /// Gets the next patch version number that follows this one.
  ///
  /// If this version is a pre-release, then it just strips the pre-release
  /// suffix. Otherwise, it increments the patch version.
  Version get nextPatch {
    if (isPreRelease) {
      return new Version(major, minor, patch);
    }

    return new Version(major, minor, patch + 1);
  }

  /// Gets the previous "tilde" (== "approximate) version for this one.
  ///
  /// Adapted from https://github.com/npm/node-semver/blob/master/semver.js:
  ///
  /// ~, ~> --> * (any, kinda silly)
  /// ~2, ~2.x, ~2.x.x, ~>2, ~>2.x ~>2.x.x --> >=2.0.0 <3.0.0
  /// ~2.0, ~2.0.x, ~>2.0, ~>2.0.x --> >=2.0.0 <2.1.0
  /// ~1.2, ~1.2.x, ~>1.2, ~>1.2.x --> >=1.2.0 <1.3.0
  /// ~1.2.3, ~>1.2.3 --> >=1.2.3 <1.3.0
  /// ~1.2.0, ~>1.2.0 --> >=1.2.0 <1.3.0
  /// NOTE: See TODO before [_isX].
  Version get prevTilde {
    if (_isX(major)) {
      return zero;
    } else if (_isX(minor)) {
      return new Version(major, 0, 0);
    } else if (_isX(patch)) {
      // ~1.2 == >=1.2.0- <1.3.0-
      return new Version(major, minor, 0);
    } else if (preRelease.isNotEmpty) {
      return new Version(major, minor, patch, pre: preRelease.join('.'));
    } else {
      // ~1.2.3 == >=1.2.3 <1.3.0
      return new Version(major, minor, patch);
    }
  }

  /// Gets the next "tilde" (== "approximate") version for this one;
  /// the opposite of [prevTilde].
  Version get nextTilde {
    if (_isX(major)) {
      return infinity;
    } else if (_isX(minor)) {
      return new Version(major + 1, 0, 0);
    } else if (_isX(patch)) {
      // ~1.2 == >=1.2.0- <1.3.0-
      return new Version(major, minor + 1, 0);
    } else if (preRelease.isNotEmpty) {
      return new Version(major, minor + 1, 0);
    } else {
      // ~1.2.3 == >=1.2.3 <1.3.0
      return new Version(major, minor + 1, 0);
    }
  }

  /// Gets the previous "caret" (== "compatible") version for this one.
  ///
  /// Adapted from https://github.com/npm/node-semver/blob/master/semver.js:
  ///
  /// ^ --> * (any, kinda silly)
  /// ^2, ^2.x, ^2.x.x --> >=2.0.0 <3.0.0
  /// ^2.0, ^2.0.x --> >=2.0.0 <3.0.0
  /// ^1.2, ^1.2.x --> >=1.2.0 <2.0.0
  /// ^1.2.3 --> >=1.2.3 <2.0.0
  /// ^1.2.0 --> >=1.2.0 <2.0.0
  /// NOTE: See TODO before [_isX].
  Version get prevCaret {
    if (_isX(major)) {
      return zero;
    } else if (_isX(minor)) {
      return new Version(major, 0, 0);
    } else if (_isX(patch)) {
      return new Version(major, minor, 0);
    } else if (preRelease.isNotEmpty) {
      return new Version(major, minor, patch, pre: preRelease.join('.'));
    } else {
      return new Version(major, minor, patch);
    }
  }

  /// Gets the next "caret" (== "compatible") version for this one;
  /// the opposite of [prevTilde].
  Version get nextCaret {
    if (_isX(major)) {
      return infinity;
    } else if (_isX(minor)) {
      return new Version(major + 1, 0, 0);
    } else if (_isX(patch)) {
      if (major == 0) {
        return new Version(major, minor + 1, 0);
      } else {
        return new Version(major + 1, minor, 0);
      }
    } else {
      if (major == 0) {
        if (minor == 0) {
          return new Version(major, minor, patch + 1);
        } else {
          return new Version(major, minor + 1, 0);
        }
      } else {
        return new Version(major + 1, 0, 0);
      }
    }
  }

  /// Tests if [other] matches this version exactly.
  bool allows(Version other) => this == other;

  VersionConstraint intersect(VersionConstraint other) {
    if (other.isEmpty) return other;

    // Intersect a version and a range.
    if (other is VersionRange) return other.intersect(this);

    // Intersecting two versions only works if they are the same.
    if (other is Version) {
      return this == other ? this : VersionConstraint.empty;
    }

    throw new ArgumentError(
        'Unknown VersionConstraint type $other.');
  }

  int compareTo(Version other) {
    if (major != other.major) return major.compareTo(other.major);
    if (minor != other.minor) return minor.compareTo(other.minor);
    if (patch != other.patch) return patch.compareTo(other.patch);

    // Pre-releases always come before no pre-release string.
    if (!isPreRelease && other.isPreRelease) return 1;
    if (!other.isPreRelease && isPreRelease) return -1;

    var comparison = _compareLists(preRelease, other.preRelease);
    if (comparison != 0) return comparison;

    // Builds always come after no build string.
    if (build.isEmpty && other.build.isNotEmpty) return -1;
    if (other.build.isEmpty && build.isNotEmpty) return 1;
    return _compareLists(build, other.build);
  }

  String toString() => _text;

  /// Compares a dot-separated component of two versions.
  ///
  /// This is used for the pre-release and build version parts. This follows
  /// Rule 12 of the Semantic Versioning spec (v2.0.0-rc.1).
  int _compareLists(List a, List b) {
    for (var i = 0; i < max(a.length, b.length); i++) {
      var aPart = (i < a.length) ? a[i] : null;
      var bPart = (i < b.length) ? b[i] : null;

      if (aPart == bPart) continue;

      // Missing parts come before present ones.
      if (aPart == null) return -1;
      if (bPart == null) return 1;

      if (aPart is num) {
        if (bPart is num) {
          // Compare two numbers.
          return aPart.compareTo(bPart);
        } else {
          // Numbers come before strings.
          return -1;
        }
      } else {
        if (bPart is num) {
          // Strings come after numbers.
          return 1;
        } else {
          // Compare two strings.
          return aPart.compareTo(bPart);
        }
      }
    }

    // The lists are entirely equal.
    return 0;
  }
}
