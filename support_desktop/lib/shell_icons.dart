import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'widgets/brand_asset.dart';

const String _kSolid = 'ShellFaSolid';
const String _kRegular = 'ShellFaRegular';
const String _kBrands = 'ShellFaBrands';

Future<void> loadShellFonts() async {
  Future<void> one(String family, String asset) async {
    try {
      final loader = FontLoader(family)..addFont(loadBrandAssetBytes(asset));
      await loader.load();
    } catch (_) {}
  }

  await Future.wait([
    one(_kSolid, 'assets/brand/shell_fa-solid-900.ttf'),
    one(_kRegular, 'assets/brand/shell_fa-regular-400.ttf'),
    one(_kBrands, 'assets/brand/shell_fa-brands-400.ttf'),
  ]);
}

class Fa {
  static const bars = IconData(0xf0c9, fontFamily: _kSolid);
  static const bell = IconData(0xf0f3, fontFamily: _kRegular);
  static const bellSolid = IconData(0xf0f3, fontFamily: _kSolid);
  static const powerOff = IconData(0xf011, fontFamily: _kSolid);
  static const chevronDown = IconData(0xf078, fontFamily: _kSolid);
  static const chevronUp = IconData(0xf077, fontFamily: _kSolid);
  static const user = IconData(0xf007, fontFamily: _kSolid);
  static const userRegular = IconData(0xf007, fontFamily: _kRegular);
  static const search = IconData(0xf002, fontFamily: _kSolid);
  static const plus = IconData(0xf067, fontFamily: _kSolid);
  static const arrowRight = IconData(0xf061, fontFamily: _kSolid);
  static const eye = IconData(0xf06e, fontFamily: _kRegular);
  static const folder = IconData(0xf07b, fontFamily: _kRegular);
  static const calendar = IconData(0xf133, fontFamily: _kRegular);
  static const check = IconData(0xf00c, fontFamily: _kSolid);
  static const checkCircle = IconData(0xf058, fontFamily: _kRegular);
  static const times = IconData(0xf00d, fontFamily: _kSolid);
  static const idCardRegular = IconData(0xf2c2, fontFamily: _kRegular);
  static const building = IconData(0xf1ad, fontFamily: _kRegular);
  static const idBadge = IconData(0xf2c1, fontFamily: _kSolid);
  static const sliders = IconData(0xf1de, fontFamily: _kSolid);
  static const signOut = IconData(0xf2f5, fontFamily: _kSolid);
  static const bullhorn = IconData(0xf0a1, fontFamily: _kSolid);
  static const sms = IconData(0xf7cd, fontFamily: _kSolid);
  static const at = IconData(0xf1fa, fontFamily: _kSolid);
  static const shareSquare = IconData(0xf14d, fontFamily: _kSolid);
  static const comments = IconData(0xf086, fontFamily: _kSolid);
  static const userTag = IconData(0xf507, fontFamily: _kSolid);
  static const checkCircleSolid = IconData(0xf058, fontFamily: _kSolid);
  static const receipt = IconData(0xf543, fontFamily: _kSolid);
  static const ticketAlt = IconData(0xf3ff, fontFamily: _kSolid);
  static const commentDots = IconData(0xf4ad, fontFamily: _kSolid);
  static const clipboardCheck = IconData(0xf46c, fontFamily: _kSolid);
  static const userLock = IconData(0xf502, fontFamily: _kSolid);
  static const userPlus = IconData(0xf234, fontFamily: _kSolid);
  static const circle = IconData(0xf111, fontFamily: _kSolid);
  static const questionCircleRegular = IconData(0xf059, fontFamily: _kRegular);

  static const th = IconData(0xf00a, fontFamily: _kSolid);
  static const codeBranch = IconData(0xf126, fontFamily: _kSolid);
  static const scroll = IconData(0xf70e, fontFamily: _kSolid);
  static const idCard = IconData(0xf2c2, fontFamily: _kSolid);
  static const blog = IconData(0xf781, fontFamily: _kSolid);
  static const fileSignature = IconData(0xf573, fontFamily: _kSolid);
  static const userTie = IconData(0xf508, fontFamily: _kSolid);
  static const key = IconData(0xf084, fontFamily: _kSolid);
  static const usersCog = IconData(0xf509, fontFamily: _kSolid);
  static const addressCard = IconData(0xf2bb, fontFamily: _kRegular);
  static const store = IconData(0xf54e, fontFamily: _kSolid);
  static const userShield = IconData(0xf505, fontFamily: _kSolid);
  static const tags = IconData(0xf02c, fontFamily: _kSolid);
  static const dollarSign = IconData(0xf155, fontFamily: _kSolid);
  static const envelope = IconData(0xf0e0, fontFamily: _kSolid);
  static const folderOpen = IconData(0xf07c, fontFamily: _kSolid);
  static const list = IconData(0xf03a, fontFamily: _kSolid);
  static const clipboardList = IconData(0xf46d, fontFamily: _kSolid);
  static const questionCircle = IconData(0xf059, fontFamily: _kSolid);
  static const barcode = IconData(0xf02a, fontFamily: _kSolid);
  static const cog = IconData(0xf013, fontFamily: _kSolid);
  static const android = IconData(0xf17b, fontFamily: _kBrands);
  static const inbox = IconData(0xf01c, fontFamily: _kSolid);
  static const gift = IconData(0xf06b, fontFamily: _kSolid);
  static const tachometerAlt = IconData(0xf3fd, fontFamily: _kSolid);
  static const tasks = IconData(0xf0ae, fontFamily: _kSolid);
  static const chartBar = IconData(0xf080, fontFamily: _kSolid);
  static const fire = IconData(0xf06d, fontFamily: _kSolid);
  static const bolt = IconData(0xf0e7, fontFamily: _kSolid);
  static const stopwatch = IconData(0xf2f2, fontFamily: _kSolid);
  static const waveSquare = IconData(0xf83e, fontFamily: _kSolid);
  static const flag = IconData(0xf024, fontFamily: _kSolid);
  static const userCog = IconData(0xf4fe, fontFamily: _kSolid);
  static const history = IconData(0xf1da, fontFamily: _kSolid);
  static const expand = IconData(0xf065, fontFamily: _kSolid);
  static const desktop = IconData(0xf108, fontFamily: _kSolid);

  static IconData nav(String name) {
    switch (name) {
      case 'gift':
        return gift;
      case 'th':
        return th;
      case 'ticket-alt':
        return ticketAlt;
      case 'comments':
        return comments;
      case 'code-branch':
        return codeBranch;
      case 'scroll':
        return scroll;
      case 'id-card':
        return idCard;
      case 'blog':
        return blog;
      case 'file-signature':
        return fileSignature;
      case 'user-plus':
        return userPlus;
      case 'user-tie':
        return userTie;
      case 'receipt':
        return receipt;
      case 'key':
        return key;
      case 'users-cog':
        return usersCog;
      case 'address-card':
        return addressCard;
      case 'store':
        return store;
      case 'user-shield':
        return userShield;
      case 'tags':
        return tags;
      case 'dollar-sign':
        return dollarSign;
      case 'envelope':
        return envelope;
      case 'folder-open':
        return folderOpen;
      case 'list':
        return list;
      case 'clipboard-list':
        return clipboardList;
      case 'question-circle':
        return questionCircle;
      case 'barcode':
        return barcode;
      case 'cog':
        return cog;
      case 'bullhorn':
        return bullhorn;
      case 'android':
        return android;
      case 'inbox':
        return inbox;
    }
    return circle;
  }
}
