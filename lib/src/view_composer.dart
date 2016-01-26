import 'view_engine.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:embla/http.dart';

abstract class TemplateLoader {
  Stream<String> load(String filename);
  Future<bool> exists(String filename);
}

class IoTemplateLoader extends TemplateLoader {
  final String templateDirectory;
  final Encoding encoding;

  IoTemplateLoader(this.templateDirectory, this.encoding);

  File file(String filename) => new File(path.join(templateDirectory, filename));

  Stream<String> load(String filename) {
    return file(filename).openRead().map(encoding.decode);
  }

  Future<bool> exists(String filename) {
    return file(filename).exists();
  }
}

class TemplateNotFoundException implements Exception {
  final String filename;

  TemplateNotFoundException(this.filename);

  String toString() => 'TemplateNotFoundException: '
      'Could not find "$filename". Did you forget to register '
      'the correct ViewEngine?';
}

class ViewComposer {
  final List<ViewEngine> engines;
  final TemplateLoader _loader;

  ViewComposer(this._loader, this.engines);

  factory ViewComposer.create({
  List<ViewEngine> engines: const [],
  String templatesDirectory: 'web',
  Encoding encoding: UTF8
  }) {
    return new ViewComposer(new IoTemplateLoader(templatesDirectory, encoding), engines);
  }

  Template render(String path, {int statusCode: 200, Request request}) {
    final linesController = new StreamController<String>();
    final contentTypeCompleter = new Completer<ContentType>();

    final template = new Template(
        statusCode,
        linesController.stream,
        contentTypeCompleter.future
    );

    if (request != null && request.context.containsKey('embla:locals')) {
      template.locals.addAll(request.context['embla:locals']);
    }

    linesController.onListen = () async {
      for (final engine in engines) {
        for (final extension in engine.extensions) {
          final pathWithExt = path + extension;
          if (await _loader.exists(pathWithExt)) {
            await engine.render(
                _loader.load(pathWithExt),
                template,
                linesController.add,
                contentTypeCompleter.complete
            );
            if (!contentTypeCompleter.isCompleted)
              contentTypeCompleter.complete(ContentType.HTML);
            await linesController.close();
            return;
          }
        }
      }
      throw new TemplateNotFoundException(path);
    };

    return template;
  }
}