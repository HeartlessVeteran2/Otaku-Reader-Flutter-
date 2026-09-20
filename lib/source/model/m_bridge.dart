// Part of this app's port of the Mangayomi extension runtime
// (https://github.com/kodjodevf/mangayomi), Apache License 2.0.
// See NOTICE and licenses/Mangayomi-Apache-2.0.txt.
//
// Files in this tree are either ported from that project -- some byte for
// byte, some modified -- or written against its contracts. NOTICE lists every
// intended difference, as Apache-2.0 section 4(b) requires. A finding here
// usually describes upstream behaviour that published extensions are written
// against, so diff against upstream before "fixing" it.

import 'dart:convert';
import 'dart:typed_data';

import 'package:html/dom.dart' hide Text;
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:js_packer/js_packer.dart';
import 'package:otaku_reader/source/model/m_document.dart';
import 'package:otaku_reader/source/http/http_extensions.dart';
import 'package:otaku_reader/source/model/m_status.dart';
import 'package:otaku_reader/source/util/crypto/crypto_aes.dart';
import 'package:otaku_reader/source/util/crypto/deobfuscator.dart';
import 'package:otaku_reader/source/util/crypto/js_unpacker.dart';
import 'package:otaku_reader/core/utils/string_extensions.dart';
import 'package:otaku_reader/source/util/reg_exp_matcher.dart';
import 'package:xpath_selector_html_parser/xpath_selector_html_parser.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:convert/convert.dart' show hex;

class WordSet {
  final List<String> words;

  WordSet(this.words);

  bool anyWordIn(String dateString) {
    return words.any(
      (word) => dateString.toLowerCase().contains(word.toLowerCase()),
    );
  }

  bool startsWith(String dateString) {
    return words.any(
      (word) => dateString.toLowerCase().startsWith(word.toLowerCase()),
    );
  }

  bool endsWith(String dateString) {
    return words.any(
      (word) => dateString.toLowerCase().endsWith(word.toLowerCase()),
    );
  }
}

class MBridge {
  static MDocument parsHtml(String html) {
    return MDocument(Document.html(html));
  }

  ///Create query by html string

  static List<String>? xpath(String html, String xpath) {
    List<String> attrs = [];
    try {
      var htmlXPath = HtmlXPath.html(html);
      var query = htmlXPath.query(xpath);
      if (query.nodes.length > 1) {
        for (var element in query.attrs) {
          attrs.add(element!.trim());
        }
      }
      //Return one attr
      else if (query.nodes.length == 1) {
        String attr = query.attr != null ? query.attr!.trim() : '';
        if (attr.isNotEmpty) {
          attrs = [attr];
        }
      }
      return attrs;
    } catch (_) {
      return [];
    }
  }

  ///Convert serie status to int
  ///[status] contains the current status of the serie
  ///[statusList] contains a list of map of many static status
  static Status parseStatus(String status, List statusList) {
    for (var element in statusList) {
      Map statusMap = {};
      statusMap = element;
      for (var element in statusMap.entries) {
        if (element.key.toString().toLowerCase().contains(
          status.toLowerCase().trim(),
        )) {
          return switch (element.value as int) {
            0 => Status.ongoing,
            1 => Status.completed,
            2 => Status.onHiatus,
            3 => Status.canceled,
            4 => Status.publishingFinished,
            _ => Status.unknown,
          };
        }
      }
    }
    return Status.unknown;
  }

  ///Unpack a JS code

  static String? unpackJs(String code) {
    try {
      final jsPacker = JSPacker(code);
      return jsPacker.unpack() ?? '';
    } catch (_) {
      return '';
    }
  }

  ///Unpack a JS code
  static String? unpackJsAndCombine(String code) {
    try {
      return JsUnpacker.unpackAndCombine(code) ?? '';
    } catch (_) {
      return '';
    }
  }

  ///GetMapValue
  static String getMapValue(String source, String attr, bool encode) {
    try {
      var map = json.decode(source) as Map<String, dynamic>;
      if (!encode) {
        return map[attr] != null ? map[attr].toString() : '';
      }
      return map[attr] != null ? jsonEncode(map[attr]) : '';
    } catch (_) {
      return '';
    }
  }

  //Parse a list of dates to millisecondsSinceEpoch
  static List parseDates(
    List value,
    String dateFormat,
    String dateFormatLocale,
  ) {
    List<dynamic> val = [];
    for (var element in value) {
      element = element.toString().trim();
      if (element.isNotEmpty) {
        val.add(element);
      }
    }
    bool error = false;
    List<dynamic> valD = [];
    for (var date in val) {
      String dateStr = '';
      if (error) {
        dateStr = DateTime.now().millisecondsSinceEpoch.toString();
      } else {
        dateStr = parseChapterDate(date, dateFormat, dateFormatLocale, (val) {
          dateFormat = val.$1;
          dateFormatLocale = val.$2;
          error = val.$3;
        });
      }
      valD.add(dateStr);
    }
    return valD;
  }

  static List sortMapList(List list, String value, int type) {
    if (type == 0) {
      list.sort((a, b) => a[value].compareTo(b[value]));
    } else if (type == 1) {
      list.sort((a, b) => b[value].compareTo(a[value]));
    }

    return list;
  }

  //Utility to use RegExp
  static String regExp(
    String expression,
    String source,
    String replace,
    int type,
    int group,
  ) {
    if (type == 0) {
      return expression.replaceAll(RegExp(source), replace);
    }
    return regCustomMatcher(expression, source, group);
  }

  static Map<String, String> decodeHeaders(String? headers) =>
      headers == null ? {} : (jsonDecode(headers) as Map).toMapStringString!;

  static final Set<String> _initializedLocales = {};

  /// Whether `initializeDateFormatting` has been run for all locales.
  ///
  /// `DateFormat(pattern, locale).parse(...)` throws `LocaleDataException`
  /// unless the locale's symbol data has been loaded first, and sources parse
  /// chapter dates in whatever locale their site publishes. Upstream only
  /// initialises a locale inside the *fallback* loop, so the first, most-likely
  /// parse -- the one using the source's own declared dateFormatLocale -- runs
  /// against uninitialised data and throws out of the whole call. MangaHere
  /// fails exactly this way: 70 entries listed, then the detail page dies on the
  /// first chapter date.
  ///
  /// Loading every locale once is cheap next to a network round trip and removes
  /// the ordering problem entirely.
  static bool _dateFormattingReady = false;

  static void _ensureDateFormatting() {
    if (_dateFormattingReady) return;
    initializeDateFormatting();
    _dateFormattingReady = true;
  }

  //Utility to use substring
  static String substringAfter(String text, String pattern) {
    return text.substringAfter(pattern);
  }

  //Utility to use substring
  static String substringBefore(String text, String pattern) {
    return text.substringBefore(pattern);
  }

  //Utility to use substring
  static String substringBeforeLast(String text, String pattern) {
    return text.substringBeforeLast(pattern);
  }

  static String substringAfterLast(String text, String pattern) {
    return text.split(pattern).last;
  }

  //Parse a chapter date to millisecondsSinceEpoch
  static String parseChapterDate(
    String date,
    String dateFormat,
    String dateFormatLocale,
    Function((String, String, bool)) newLocale,
  ) {
    _ensureDateFormatting();

    int parseRelativeDate(String date) {
      final number = int.tryParse(RegExp(r'(\d+)').firstMatch(date)!.group(0)!);
      if (number == null) return 0;
      final cal = DateTime.now();

      if (WordSet([
        'hari',
        'gün',
        'jour',
        'día',
        'dia',
        'day',
        'วัน',
        'ngày',
        'giorni',
        'أيام',
        '天',
      ]).anyWordIn(date)) {
        return cal.subtract(Duration(days: number)).millisecondsSinceEpoch;
      } else if (WordSet([
        'jam',
        'saat',
        'heure',
        'hora',
        'hour',
        'ชั่วโมง',
        'giờ',
        'ore',
        'ساعة',
        '小时',
      ]).anyWordIn(date)) {
        return cal.subtract(Duration(hours: number)).millisecondsSinceEpoch;
      } else if (WordSet([
        'menit',
        'dakika',
        'min',
        'minute',
        'minuto',
        'นาที',
        'دقائق',
      ]).anyWordIn(date)) {
        return cal.subtract(Duration(minutes: number)).millisecondsSinceEpoch;
      } else if (WordSet(['detik', 'segundo', 'second', 'วินาที', 'sec'])
          .anyWordIn(date)) {
        return cal.subtract(Duration(seconds: number)).millisecondsSinceEpoch;
      } else if (WordSet(['week', 'semana']).anyWordIn(date)) {
        return cal.subtract(Duration(days: number * 7)).millisecondsSinceEpoch;
      } else if (WordSet(['month', 'mes']).anyWordIn(date)) {
        return cal.subtract(Duration(days: number * 30)).millisecondsSinceEpoch;
      } else if (WordSet(['year', 'año']).anyWordIn(date)) {
        return cal
            .subtract(Duration(days: number * 365))
            .millisecondsSinceEpoch;
      } else {
        return 0;
      }
    }

    try {
      if (WordSet(['yesterday', 'يوم واحد']).startsWith(date)) {
        DateTime cal = DateTime.now().subtract(const Duration(days: 1));
        cal = DateTime(cal.year, cal.month, cal.day);
        return cal.millisecondsSinceEpoch.toString();
      } else if (WordSet(['today']).startsWith(date)) {
        DateTime cal = DateTime.now();
        cal = DateTime(cal.year, cal.month, cal.day);
        return cal.millisecondsSinceEpoch.toString();
      } else if (WordSet(['يومين']).startsWith(date)) {
        DateTime cal = DateTime.now().subtract(const Duration(days: 2));
        cal = DateTime(cal.year, cal.month, cal.day);
        return cal.millisecondsSinceEpoch.toString();
      } else if (WordSet(['ago', 'atrás', 'önce', 'قبل']).endsWith(date)) {
        return parseRelativeDate(date).toString();
      } else if (WordSet(['hace']).startsWith(date)) {
        return parseRelativeDate(date).toString();
      } else if (date.contains(RegExp(r'\d(st|nd|rd|th)'))) {
        final cleanedDate = date
            .split(' ')
            .map(
              (it) => it.contains(RegExp(r'\d\D\D'))
                  ? it.replaceAll(RegExp(r'\D'), '')
                  : it,
            )
            .join(' ');
        return DateFormat(
          dateFormat,
          dateFormatLocale,
        ).parse(cleanedDate).millisecondsSinceEpoch.toString();
      } else {
        return DateFormat(
          dateFormat,
          dateFormatLocale,
        ).parse(date).millisecondsSinceEpoch.toString();
      }
    } catch (e) {
      final supportedLocales = DateFormat.allLocalesWithSymbols();

      for (var locale in supportedLocales) {
        for (var dateFormat in _dateFormats) {
          newLocale((dateFormat, locale, false));
          try {
            if (!_initializedLocales.contains(locale)) {
              initializeDateFormatting(locale);
              _initializedLocales.add(locale);
            }
            if (WordSet(['yesterday', 'يوم واحد']).startsWith(date)) {
              DateTime cal = DateTime.now().subtract(const Duration(days: 1));
              cal = DateTime(cal.year, cal.month, cal.day);
              return cal.millisecondsSinceEpoch.toString();
            } else if (WordSet(['today']).startsWith(date)) {
              DateTime cal = DateTime.now();
              cal = DateTime(cal.year, cal.month, cal.day);
              return cal.millisecondsSinceEpoch.toString();
            } else if (WordSet(['يومين']).startsWith(date)) {
              DateTime cal = DateTime.now().subtract(const Duration(days: 2));
              cal = DateTime(cal.year, cal.month, cal.day);
              return cal.millisecondsSinceEpoch.toString();
            } else if (WordSet(['ago', 'atrás', 'önce', 'قبل'])
                .endsWith(date)) {
              return parseRelativeDate(date).toString();
            } else if (WordSet(['hace']).startsWith(date)) {
              return parseRelativeDate(date).toString();
            } else if (date.contains(RegExp(r'\d(st|nd|rd|th)'))) {
              final cleanedDate = date
                  .split(' ')
                  .map(
                    (it) => it.contains(RegExp(r'\d\D\D'))
                        ? it.replaceAll(RegExp(r'\D'), '')
                        : it,
                  )
                  .join(' ');
              return DateFormat(
                dateFormat,
                locale,
              ).parse(cleanedDate).millisecondsSinceEpoch.toString();
            } else {
              return DateFormat(
                dateFormat,
                locale,
              ).parse(date).millisecondsSinceEpoch.toString();
            }
          } catch (_) {}
        }
      }
      newLocale((dateFormat, dateFormatLocale, true));
      return DateTime.now().millisecondsSinceEpoch.toString();
    }
  }

  static String deobfuscateJsPassword(String inputString) {
    return Deobfuscator.deobfuscateJsPassword(inputString);
  }

  static String encryptAESCryptoJS(String plainText, String passphrase) {
    return CryptoAES.encryptAESCryptoJS(plainText, passphrase);
  }

  static String decryptAESCryptoJS(String encrypted, String passphrase) {
    return CryptoAES.decryptAESCryptoJS(encrypted, passphrase);
  }

  /// AES-GCM decryption for extensions (parity with Java's
  /// `Cipher.getInstance("AES/GCM/NoPadding")`).
  ///
  /// - [encrypted] : base64 ciphertext. If the 16-byte GCM auth tag is already
  ///                 appended to it (as Java's `Cipher.doFinal` produces),
  ///                 pass an empty [tagHex].
  /// - [keyHex]    : hex-encoded key (16/24/32 bytes → AES-128/192/256)
  /// - [ivHex]     : hex-encoded IV / nonce (typically 12 bytes for GCM)
  /// - [tagHex]    : hex-encoded auth tag (usually 16 bytes), appended to the
  ///                 ciphertext before decryption; empty if already appended
  ///
  /// Returns the decrypted UTF-8 string, or the original [encrypted] input if
  /// decryption/authentication fails (mirrors [cryptoHandler]'s behavior).
  static String decryptAESGCM(
    String encrypted,
    String keyHex,
    String ivHex,
    String tagHex,
  ) {
    try {
      final key = encrypt.Key(Uint8List.fromList(hex.decode(keyHex)));
      final iv = encrypt.IV(Uint8List.fromList(hex.decode(ivHex)));
      // PointyCastle's GCM (and Java's AES/GCM/NoPadding) expect the 128-bit
      // auth tag appended to the ciphertext, so concatenate the two.
      final dataWithTag = Uint8List.fromList([
        ...base64.decode(encrypted),
        ...hex.decode(tagHex),
      ]);
      final encrypter = encrypt.Encrypter(
        encrypt.AES(key, mode: encrypt.AESMode.gcm),
      );
      return encrypter.decrypt(encrypt.Encrypted(dataWithTag), iv: iv);
    } catch (_) {
      return encrypted;
    }
  }

  static String cryptoHandler(
    String text,
    String iv,
    String secretKeyString,
    bool encrypt,
  ) {
    try {
      if (encrypt) {
        final encryptt = _encrypt(secretKeyString, iv);
        final en = encryptt.$1.encrypt(text, iv: encryptt.$2);
        return en.base64;
      } else {
        final encryptt = _encrypt(secretKeyString, iv);
        final en = encryptt.$1.decrypt64(text, iv: encryptt.$2);
        return en;
      }
    } catch (_) {
      return text;
    }
  }
}

final List<String> _dateFormats = [
  'dd/MM/yyyy',
  'MM/dd/yyyy',
  'yyyy/MM/dd',
  'dd-MM-yyyy',
  'MM-dd-yyyy',
  'yyyy-MM-dd',
  'dd.MM.yyyy',
  'MM.dd.yyyy',
  'yyyy.MM.dd',
  'dd MMMM yyyy',
  'MMMM dd, yyyy',
  'yyyy MMMM dd',
  'dd MMM yyyy',
  'MMM dd yyyy',
  'yyyy MMM dd',
  'dd MMMM, yyyy',
  'yyyy, MMMM dd',
  'MMMM dd yyyy',
  'MMM dd, yyyy',
  'dd LLLL yyyy',
  'LLLL dd, yyyy',
  'yyyy LLLL dd',
  'LLLL dd yyyy',
  'MMMMM dd, yyyy',
  'MMM d, yyy',
  'MMM d, yyyy',
  'dd/mm/yyyy',
  'd MMMM yyyy',
  "dd 'de' MMMM 'de' yyyy",
  "d MMMM'،' yyyy",
  "yyyy'年'M'月'd",
  'd MMMM, yyyy',
  "dd 'de' MMMMM 'de' yyyy",
  'dd MMMMM, yyyy',
  'MMMM d, yyyy',
  'MMM dd,yyyy',
];

(encrypt.Encrypter, encrypt.IV) _encrypt(String keyy, String ivv) {
  final key = encrypt.Key.fromUtf8(keyy);
  final iv = encrypt.IV.fromUtf8(ivv);
  final encrypter = encrypt.Encrypter(
    encrypt.AES(key, mode: encrypt.AESMode.cbc, padding: 'PKCS7'),
  );
  return (encrypter, iv);
}
