// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// @dart = 2.8

import 'package:flutter_tools/src/base/common.dart' show ToolExit;
import 'package:flutter_tools/src/base/file_system.dart';
import 'package:flutter_tools/src/base/io.dart';
import 'package:flutter_tools/src/base/platform.dart';
import 'package:flutter_tools/src/cache.dart';
import 'package:flutter_tools/src/commands/upgrade.dart';
import 'package:flutter_tools/src/convert.dart';
import 'package:flutter_tools/src/globals_null_migrated.dart' as globals;
import 'package:flutter_tools/src/persistent_tool_state.dart';
import 'package:flutter_tools/src/runner/flutter_command.dart';
import 'package:flutter_tools/src/version.dart';

import '../../src/common.dart';
import '../../src/context.dart';
import '../../src/fake_process_manager.dart';
import '../../src/fakes.dart';
import '../../src/test_flutter_command_runner.dart';

void main() {
  group('UpgradeCommandRunner', () {
    FakeUpgradeCommandRunner fakeCommandRunner;
    UpgradeCommandRunner realCommandRunner;
    FakeProcessManager processManager;
    FakePlatform fakePlatform;
    const GitTagVersion gitTagVersion = GitTagVersion(
      x: 1,
      y: 2,
      z: 3,
      hotfix: 4,
      commits: 5,
      hash: 'asd',
    );

    setUp(() {
      fakeCommandRunner = FakeUpgradeCommandRunner();
      realCommandRunner = UpgradeCommandRunner();
      processManager = FakeProcessManager.empty();
      fakeCommandRunner.willHaveUncommittedChanges = false;
      fakePlatform = FakePlatform()..environment = Map<String, String>.unmodifiable(<String, String>{
        'ENV1': 'irrelevant',
        'ENV2': 'irrelevant',
      });
    });

    testUsingContext('throws on unknown tag, official branch,  noforce', () async {
      final FakeFlutterVersion flutterVersion = FakeFlutterVersion(channel: 'dev');
      const String upstreamRevision = '';
      final FakeFlutterVersion latestVersion = FakeFlutterVersion(frameworkRevision: upstreamRevision);
      fakeCommandRunner.remoteVersion = latestVersion;

      final Future<FlutterCommandResult> result = fakeCommandRunner.runCommand(
        force: false,
        continueFlow: false,
        testFlow: false,
        gitTagVersion: const GitTagVersion.unknown(),
        flutterVersion: flutterVersion,
        verifyOnly: false,
      );
      expect(result, throwsToolExit());
      expect(processManager, hasNoRemainingExpectations);
    }, overrides: <Type, Generator>{
      Platform: () => fakePlatform,
    });

    testUsingContext('throws tool exit with uncommitted changes', () async {
      final FakeFlutterVersion flutterVersion = FakeFlutterVersion(channel: 'dev');
      const String upstreamRevision = '';
      final FakeFlutterVersion latestVersion = FakeFlutterVersion(frameworkRevision: upstreamRevision);
      fakeCommandRunner.remoteVersion = latestVersion;
      fakeCommandRunner.willHaveUncommittedChanges = true;

      final Future<FlutterCommandResult> result = fakeCommandRunner.runCommand(
        force: false,
        continueFlow: false,
        testFlow: false,
        gitTagVersion: gitTagVersion,
        flutterVersion: flutterVersion,
        verifyOnly: false,
      );
      expect(result, throwsToolExit());
      expect(processManager, hasNoRemainingExpectations);
    }, overrides: <Type, Generator>{
      Platform: () => fakePlatform,
    });

    testUsingContext("Doesn't continue on known tag, dev branch, no force, already up-to-date", () async {
      const String revision = 'abc123';
      final FakeFlutterVersion latestVersion = FakeFlutterVersion(frameworkRevision: revision);
      final FakeFlutterVersion flutterVersion = FakeFlutterVersion(channel: 'dev', frameworkRevision: revision);
      fakeCommandRunner.alreadyUpToDate = true;
      fakeCommandRunner.remoteVersion = latestVersion;

      final Future<FlutterCommandResult> result = fakeCommandRunner.runCommand(
        force: false,
        continueFlow: false,
        testFlow: false,
        gitTagVersion: gitTagVersion,
        flutterVersion: flutterVersion,
        verifyOnly: false,
      );
      expect(await result, FlutterCommandResult.success());
      expect(testLogger.statusText, contains('Flutter is already up to date'));
      expect(processManager, hasNoRemainingExpectations);
    }, overrides: <Type, Generator>{
      ProcessManager: () => processManager,
      Platform: () => fakePlatform,
    });

    testUsingContext('correctly provides upgrade version on verify only', () async {
      const String revision = 'abc123';
      const String upstreamRevision = 'def456';
      const String version = '1.2.3';
      const String upstreamVersion = '4.5.6';

      final FakeFlutterVersion flutterVersion = FakeFlutterVersion(
        channel: 'dev',
        frameworkRevision: revision,
        frameworkRevisionShort: revision,
        frameworkVersion: version,
      );

      final FakeFlutterVersion latestVersion = FakeFlutterVersion(
        frameworkRevision: upstreamRevision,
        frameworkRevisionShort: upstreamRevision,
        frameworkVersion: upstreamVersion,
      );

      fakeCommandRunner.alreadyUpToDate = false;
      fakeCommandRunner.remoteVersion = latestVersion;

      final Future<FlutterCommandResult> result = fakeCommandRunner.runCommand(
        force: false,
        continueFlow: false,
        testFlow: false,
        gitTagVersion: gitTagVersion,
        flutterVersion: flutterVersion,
        verifyOnly: true,
      );
      expect(await result, FlutterCommandResult.success());
      expect(testLogger.statusText, contains('A new version of Flutter is available'));
      expect(testLogger.statusText, contains('The latest version: 4.5.6 (revision def456)'));
      expect(testLogger.statusText, contains('Your current version: 1.2.3 (revision abc123)'));
      expect(processManager, hasNoRemainingExpectations);
    }, overrides: <Type, Generator>{
      ProcessManager: () => processManager,
      Platform: () => fakePlatform,
    });

    testUsingContext('fetchLatestVersion returns version if git succeeds', () async {
      const String revision = 'abc123';
      const String version = '1.2.3';

      processManager.addCommands(<FakeCommand>[
        const FakeCommand(command: <String>[
          'git', 'fetch', '--tags'
        ]),
        const FakeCommand(command: <String>[
          'git', 'rev-parse', '--verify', '@{u}',
        ],
        stdout: revision),
        const FakeCommand(command: <String>[
          'git', 'tag', '--points-at', revision,
        ],
        stdout: ''),
        const FakeCommand(command: <String>[
          'git', 'describe', '--match', '*.*.*', '--long', '--tags', revision,
        ],
        stdout: version),
      ]);

      final FlutterVersion updateVersion = await realCommandRunner.fetchLatestVersion(localVersion: FakeFlutterVersion());

      expect(updateVersion.frameworkVersion, version);
      expect(updateVersion.frameworkRevision, revision);
      expect(processManager, hasNoRemainingExpectations);
    }, overrides: <Type, Generator>{
      ProcessManager: () => processManager,
      Platform: () => fakePlatform,
    });

    testUsingContext('fetchLatestVersion throws toolExit if HEAD is detached', () async {
      processManager.addCommands(const <FakeCommand>[
        FakeCommand(command: <String>[
          'git', 'fetch', '--tags'
        ]),
        FakeCommand(
          command: <String>['git', 'rev-parse', '--verify', '@{u}'],
          exception: ProcessException(
            'git',
            <String>['rev-parse', '--verify', '@{u}'],
            'fatal: HEAD does not point to a branch',
          ),
        ),
      ]);

      ToolExit err;
      try {
        await realCommandRunner.fetchLatestVersion(localVersion: FakeFlutterVersion());
      } on ToolExit catch (e) {
        err = e;
      }
      expect(err, isNotNull);
      expect(err.toString(), contains('Unable to upgrade Flutter: HEAD does not point to a branch'));
      expect(err.toString(), contains('Use "flutter channel" to switch to an official channel ("stable", "beta", "dev", or "master") and retry'));
      // FakeFlutterVersion.getBranchName is hardcoded to 'master'
      expect(err.toString(), contains('flutter channel stable'));
      expect(err.toString(), contains('re-install Flutter by going to https://flutter.dev/docs/get-started/install'));
      expect(processManager, hasNoRemainingExpectations);
    }, overrides: <Type, Generator>{
      ProcessManager: () => processManager,
      Platform: () => fakePlatform,
    });

    testUsingContext('fetchLatestVersion throws toolExit if no upstream configured', () async {
      realCommandRunner.workingDirectory = '/src/flutter';

      processManager.addCommands(const <FakeCommand>[
        FakeCommand(command: <String>[
          'git', 'fetch', '--tags'
        ]),
        FakeCommand(
          command: <String>['git', 'rev-parse', '--verify', '@{u}'],
          exception: ProcessException(
            'git',
            <String>['rev-parse', '--verify', '@{u}'],
            'fatal: no upstream configured for branch',
          ),
        ),
      ]);

      ToolExit err;
      try {
        await realCommandRunner.fetchLatestVersion(localVersion: FakeFlutterVersion());
      } on ToolExit catch (e) {
        err = e;
      }
      expect(err, isNotNull);
      expect(err.toString(), contains('Unable to upgrade Flutter: No upstream repository configured for branch.'));
      expect(err.toString(), contains('Run "git remote add origin https://github.com/flutter/flutter.git"'));
      // FakeFlutterVersion.getBranchName is hardcoded to 'master'
      expect(err.toString(), contains('and "git branch --set-upstream-to=origin/master"'));
      expect(err.toString(), contains('if remote "origin" exists in /src/flutter'));
      expect(err.toString(), contains('re-install Flutter by going to https://flutter.dev/docs/get-started/install'));
      expect(processManager, hasNoRemainingExpectations);
    }, overrides: <Type, Generator>{
      ProcessManager: () => processManager,
      Platform: () => fakePlatform,
    });

    group('verifyStandardRemote', () {
      const String flutterStandardUrlDotGit = 'https://github.com/flutter/flutter.git';
      const String flutterNonStandardUrlDotGit = 'https://githubmirror.com/flutter/flutter.git';
      const String flutterStandardUrl = 'https://github.com/flutter/flutter';

      testUsingContext('does not throw toolExit at standard remote url with .git suffix and FLUTTER_GIT_URL unset', () async {
        final FakeFlutterVersion flutterVersion = FakeFlutterVersion(
          channel: 'dev',
          repositoryUrl: flutterStandardUrlDotGit,
        );

        ToolExit err;
        try {
         realCommandRunner.verifyStandardRemote(flutterVersion);
        } on ToolExit catch (e) {
          err = e;
        }
        expect(err, isNull);
        expect(processManager, hasNoRemainingExpectations);
      }, overrides: <Type, Generator> {
        ProcessManager: () => processManager,
        Platform: () => fakePlatform,
      });

      testUsingContext('does not throw toolExit at standard remote url without .git suffix and FLUTTER_GIT_URL unset', () async {
        final FakeFlutterVersion flutterVersion = FakeFlutterVersion(
          channel: 'dev',
          repositoryUrl: flutterStandardUrl,
        );

        ToolExit err;
        try {
         realCommandRunner.verifyStandardRemote(flutterVersion);
        } on ToolExit catch (e) {
          err = e;
        }
        expect(err, isNull);
        expect(processManager, hasNoRemainingExpectations);
      }, overrides: <Type, Generator> {
        ProcessManager: () => processManager,
        Platform: () => fakePlatform,
      });

      testUsingContext('throws toolExit at non-standard remote url with FLUTTER_GIT_URL unset', () async {
        final FakeFlutterVersion flutterVersion = FakeFlutterVersion(
          channel: 'dev',
          repositoryUrl: flutterNonStandardUrlDotGit,
        );

        ToolExit err;
        try {
         realCommandRunner.verifyStandardRemote(flutterVersion);
        } on ToolExit catch (e) {
          err = e;
        }
        expect(err, isNotNull);
        expect(err.toString(), contains('The Flutter SDK is tracking a non-standard remote "$flutterNonStandardUrlDotGit"'));
        expect(err.toString(), contains('set the environment variable "FLUTTER_GIT_URL" to "$flutterNonStandardUrlDotGit", and retry.'));
        expect(err.toString(), contains('change the url of the tracking remote to "https://github.com/flutter/flutter.git", and retry,'));
        expect(err.toString(), contains('git remote set-url origin https://github.com/flutter/flutter.git'));
        expect(err.toString(), contains('re-install Flutter by going to https://flutter.dev/docs/get-started/install'));
        expect(processManager, hasNoRemainingExpectations);
      }, overrides: <Type, Generator> {
        ProcessManager: () => processManager,
        Platform: () => fakePlatform,
      });

      testUsingContext('does not throw toolExit at non-standard remote url with FLUTTER_GIT_URL set', () async {
        final FakeFlutterVersion flutterVersion = FakeFlutterVersion(
          channel: 'dev',
          repositoryUrl: flutterNonStandardUrlDotGit,
        );

        ToolExit err;
        try {
         realCommandRunner.verifyStandardRemote(flutterVersion);
        } on ToolExit catch (e) {
          err = e;
        }
        expect(err, isNull);
        expect(processManager, hasNoRemainingExpectations);
      }, overrides: <Type, Generator> {
        ProcessManager: () => processManager,
        Platform: () => fakePlatform..environment = Map<String, String>.unmodifiable(<String, String> {
          'FLUTTER_GIT_URL': flutterNonStandardUrlDotGit,
        }),
      });

      testUsingContext('throws toolExit at remote url and FLUTTER_GIT_URL set to different urls', () async {
        final FakeFlutterVersion flutterVersion = FakeFlutterVersion(
          channel: 'dev',
          repositoryUrl: flutterNonStandardUrlDotGit,
        );

        ToolExit err;
        try {
         realCommandRunner.verifyStandardRemote(flutterVersion);
        } on ToolExit catch (e) {
          err = e;
        }
        expect(err, isNotNull);
        expect(err.toString(), contains('The Flutter SDK is tracking "$flutterNonStandardUrlDotGit"'));
        expect(err.toString(), contains('but "FLUTTER_GIT_URL" is set to "$flutterStandardUrl"'));
        expect(err.toString(), contains('remove "FLUTTER_GIT_URL" from the environment or set "FLUTTER_GIT_URL" to "$flutterNonStandardUrlDotGit"'));
        expect(err.toString(), contains('re-install Flutter by going to https://flutter.dev/docs/get-started/install'));
        expect(processManager, hasNoRemainingExpectations);
      }, overrides: <Type, Generator> {
        ProcessManager: () => processManager,
        Platform: () => fakePlatform..environment = Map<String, String>.unmodifiable(<String, String> {
          'FLUTTER_GIT_URL': flutterStandardUrl,
        }),
      });
    });

    testUsingContext('git exception during attemptReset throwsToolExit', () async {
      const String revision = 'abc123';
      const String errorMessage = 'fatal: Could not parse object ´$revision´';
      processManager.addCommand(
        const FakeCommand(
          command: <String>['git', 'reset', '--hard', revision],
          exception: ProcessException(
            'git',
            <String>['reset', '--hard', revision],
            errorMessage,
          ),
        ),
      );

      await expectLater(
            () async => realCommandRunner.attemptReset(revision),
        throwsToolExit(message: errorMessage),
      );
      expect(processManager, hasNoRemainingExpectations);
    }, overrides: <Type, Generator>{
      ProcessManager: () => processManager,
      Platform: () => fakePlatform,
    });

    testUsingContext('flutterUpgradeContinue passes env variables to child process', () async {
      processManager.addCommand(
        FakeCommand(
          command: <String>[
            globals.fs.path.join('bin', 'flutter'),
            'upgrade',
            '--continue',
            '--no-version-check',
          ],
          environment: <String, String>{'FLUTTER_ALREADY_LOCKED': 'true', ...fakePlatform.environment}
        ),
      );
      await realCommandRunner.flutterUpgradeContinue();
      expect(processManager, hasNoRemainingExpectations);
    }, overrides: <Type, Generator>{
      ProcessManager: () => processManager,
      Platform: () => fakePlatform,
    });

    testUsingContext('Show current version to the upgrade message.', () async {
      const String revision = 'abc123';
      const String upstreamRevision = 'def456';
      const String version = '1.2.3';
      const String upstreamVersion = '4.5.6';

      final FakeFlutterVersion flutterVersion = FakeFlutterVersion(
        channel: 'dev',
        frameworkRevision: revision,
        frameworkVersion: version,
      );
      final FakeFlutterVersion latestVersion = FakeFlutterVersion(
        frameworkRevision: upstreamRevision,
        frameworkVersion: upstreamVersion,
      );

      fakeCommandRunner.alreadyUpToDate = false;
      fakeCommandRunner.remoteVersion = latestVersion;
      fakeCommandRunner.workingDirectory = 'workingDirectory/aaa/bbb';

      final Future<FlutterCommandResult> result = fakeCommandRunner.runCommand(
        force: true,
        continueFlow: false,
        testFlow: true,
        gitTagVersion: gitTagVersion,
        flutterVersion: flutterVersion,
        verifyOnly: false,
      );
      expect(await result, FlutterCommandResult.success());
      expect(testLogger.statusText, contains('Upgrading Flutter to 4.5.6 from 1.2.3 in workingDirectory/aaa/bbb...'));
    }, overrides: <Type, Generator>{
      ProcessManager: () => processManager,
      Platform: () => fakePlatform,
    });

    testUsingContext('precacheArtifacts passes env variables to child process', () async {
      processManager.addCommand(
        FakeCommand(
          command: <String>[
            globals.fs.path.join('bin', 'flutter'),
            '--no-color',
            '--no-version-check',
            'precache',
          ],
          environment: <String, String>{'FLUTTER_ALREADY_LOCKED': 'true', ...fakePlatform.environment}
        ),
      );
      await realCommandRunner.precacheArtifacts();
      expect(processManager, hasNoRemainingExpectations);
    }, overrides: <Type, Generator>{
      ProcessManager: () => processManager,
      Platform: () => fakePlatform,
    });

    group('runs upgrade', () {
      setUp(() {
        processManager.addCommand(
          FakeCommand(command: <String>[
            globals.fs.path.join('bin', 'flutter'),
            'upgrade',
            '--continue',
            '--no-version-check',
          ]),
        );
      });

      testUsingContext('does not throw on unknown tag, official branch, force', () async {
        fakeCommandRunner.remoteVersion = FakeFlutterVersion(frameworkRevision: null);
        final FakeFlutterVersion flutterVersion = FakeFlutterVersion(channel: 'dev');

        final Future<FlutterCommandResult> result = fakeCommandRunner.runCommand(
          force: true,
          continueFlow: false,
          testFlow: false,
          gitTagVersion: const GitTagVersion.unknown(),
          flutterVersion: flutterVersion,
          verifyOnly: false,
        );
        expect(await result, FlutterCommandResult.success());
        expect(processManager, hasNoRemainingExpectations);
      }, overrides: <Type, Generator>{
        ProcessManager: () => processManager,
        Platform: () => fakePlatform,
      });

      testUsingContext('does not throw tool exit with uncommitted changes and force', () async {
        final FakeFlutterVersion flutterVersion = FakeFlutterVersion(channel: 'dev');
        fakeCommandRunner.remoteVersion = FakeFlutterVersion(frameworkRevision: null);
        fakeCommandRunner.willHaveUncommittedChanges = true;

        final Future<FlutterCommandResult> result = fakeCommandRunner.runCommand(
          force: true,
          continueFlow: false,
          testFlow: false,
          gitTagVersion: gitTagVersion,
          flutterVersion: flutterVersion,
          verifyOnly: false,
        );
        expect(await result, FlutterCommandResult.success());
        expect(processManager, hasNoRemainingExpectations);
      }, overrides: <Type, Generator>{
        ProcessManager: () => processManager,
        Platform: () => fakePlatform,
      });

      testUsingContext("Doesn't throw on known tag, dev branch, no force", () async {
        final FakeFlutterVersion flutterVersion = FakeFlutterVersion(channel: 'dev');
        fakeCommandRunner.remoteVersion = FakeFlutterVersion(frameworkRevision: null);

        final Future<FlutterCommandResult> result = fakeCommandRunner.runCommand(
          force: false,
          continueFlow: false,
          testFlow: false,
          gitTagVersion: gitTagVersion,
          flutterVersion: flutterVersion,
          verifyOnly: false,
        );
        expect(await result, FlutterCommandResult.success());
        expect(processManager, hasNoRemainingExpectations);
      }, overrides: <Type, Generator>{
        ProcessManager: () => processManager,
        Platform: () => fakePlatform,
      });

      group('full command', () {
        FakeProcessManager fakeProcessManager;
        Directory tempDir;
        File flutterToolState;

        setUp(() {
          Cache.disableLocking();
          fakeProcessManager = FakeProcessManager.list(<FakeCommand>[
            const FakeCommand(
              command: <String>[
                'git', 'tag', '--points-at', 'HEAD',
              ],
              stdout: '',
            ),
            const FakeCommand(
              command: <String>[
                'git', 'describe', '--match', '*.*.*', '--long', '--tags', 'HEAD',
              ],
              stdout: 'v1.12.16-19-gb45b676af',
            ),
          ]);
          tempDir = globals.fs.systemTempDirectory.createTempSync('flutter_upgrade_test.');
          flutterToolState = tempDir.childFile('.flutter_tool_state');
        });

        tearDown(() {
          Cache.enableLocking();
          tryToDelete(tempDir);
        });

        testUsingContext('upgrade continue prints welcome message', () async {
          final UpgradeCommand upgradeCommand = UpgradeCommand(
            verboseHelp: false,
            commandRunner: fakeCommandRunner,
          );

          await createTestCommandRunner(upgradeCommand).run(
            <String>[
              'upgrade',
              '--continue',
            ],
          );

          expect(
            json.decode(flutterToolState.readAsStringSync()),
            containsPair('redisplay-welcome-message', true),
          );
        }, overrides: <Type, Generator>{
          FlutterVersion: () => FakeFlutterVersion(),
          ProcessManager: () => fakeProcessManager,
          PersistentToolState: () => PersistentToolState.test(
            directory: tempDir,
            logger: testLogger,
          ),
        });
      });
    });

  });
}

class FakeUpgradeCommandRunner extends UpgradeCommandRunner {
  bool willHaveUncommittedChanges = false;
  bool alreadyUpToDate = false;

  FlutterVersion remoteVersion;

  @override
  Future<FlutterVersion> fetchLatestVersion({FlutterVersion localVersion}) async => remoteVersion;

  @override
  Future<bool> hasUncommittedChanges() async => willHaveUncommittedChanges;

  @override
  Future<void> attemptReset(String newRevision) async {}

  @override
  Future<void> precacheArtifacts() async {}

  @override
  Future<void> updatePackages(FlutterVersion flutterVersion) async {}

  @override
  Future<void> runDoctor() async {}
}
