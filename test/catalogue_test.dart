import 'dart:typed_data';

import 'package:course_vault/mega/catalogue.dart';
import 'package:flutter_test/flutter_test.dart';

MegaNode dir(String name, [List<MegaNode> children = const []]) {
  final node = MegaNode(
    handle: name,
    parentHandle: null,
    isDir: true,
    name: name,
    size: 0,
    key: Uint8List(16),
  );
  node.children.addAll(children);
  return node;
}

MegaNode file(String name, {int size = 1000}) => MegaNode(
      handle: name,
      parentHandle: null,
      isDir: false,
      name: name,
      size: size,
      key: Uint8List(32),
    );

void main() {
  group('buildCatalogue', () {
    test('nested course > module > lessons', () {
      final target = dir('Library', [
        dir('01-Creative Strategy Program', [
          dir('01-0 Mindset', [
            file('01-Welcome.mp4', size: 5000),
            file('01-Welcome.pdf'),
            file('02-Discipline.mp4'),
          ]),
          dir('02-1 Basics', [
            file('01-What is a Strategist.mp4'),
          ]),
        ]),
      ]);
      final courses = buildCatalogue(target);
      expect(courses.length, 1);
      expect(courses.first.name, 'Creative Strategy Program');
      expect(courses.first.modules.length, 2);
      expect(courses.first.modules.first.lessons.length, 2);
      final first = courses.first.modules.first.lessons.first;
      expect(first.name, 'Welcome');
      expect(first.hasVideo, isTrue);
      expect(first.resources.length, 1); // the .pdf
      expect(first.resources.first.name, '01-Welcome.pdf');
    });

    test('flat layout: videos directly in a course folder', () {
      final target = dir('Library', [
        dir('My Course', [
          file('01-Intro.mp4'),
          file('02-Advanced.mp4'),
        ]),
      ]);
      final courses = buildCatalogue(target);
      expect(courses.length, 1);
      expect(courses.first.modules.length, 1);
      expect(courses.first.modules.first.lessons.length, 2);
    });

    test('flat layout: videos directly in the linked folder', () {
      final target = dir('My Library', [
        file('01-Intro.mp4'),
        file('02-Advanced.mp4'),
      ]);
      final courses = buildCatalogue(target);
      expect(courses.length, 1);
      expect(courses.first.name, 'My Library');
      expect(courses.first.modules.first.lessons.length, 2);
    });

    test('document-only stems become document lessons', () {
      final target = dir('Library', [
        dir('Course', [
          dir('Module', [
            file('01-Guide.pdf'),
            file('02-Video.mp4'),
          ]),
        ]),
      ]);
      final courses = buildCatalogue(target);
      final lessons = courses.first.modules.first.lessons;
      expect(lessons.length, 2);
      expect(lessons.first.hasVideo, isFalse);
      expect(lessons.first.resources.first.name, '01-Guide.pdf');
    });

    test('empty folders are dropped', () {
      final target = dir('Library', [
        dir('Empty Course', [dir('Empty Module', [])]),
        dir('Real Course', [
          dir('Module', [file('01-Lesson.mp4')]),
        ]),
      ]);
      final courses = buildCatalogue(target);
      expect(courses.length, 1);
      expect(courses.first.name, 'Real Course');
    });

    test('splitPrefix mirrors the desktop scanner', () {
      expect(splitPrefix('01 - Intro').order, 1);
      expect(splitPrefix('01 - Intro').title, 'Intro');
      expect(splitPrefix('02-5 Character Skills').title, '5 Character Skills');
      expect(splitPrefix('No Prefix').order, 9999);
    });
  });
}
