import Foundation

/// Offline festival labels for the Today calendar.
///
/// These are display labels rather than statutory workday/holiday schedules,
/// so they never require a network request or access to the user's calendars.
enum QingxuFestivalCalendar {
  private static let solarFestivals: [Int: String] = [
    101: "元旦",
    308: "妇女节",
    501: "劳动节",
    504: "青年节",
    601: "儿童节",
    701: "建党节",
    801: "建军节",
    910: "教师节",
    1001: "国庆节"
  ]

  private static let lunarFestivals: [Int: String] = [
    101: "春节",
    115: "元宵节",
    505: "端午节",
    707: "七夕",
    715: "中元节",
    815: "中秋节",
    909: "重阳节",
    1208: "腊八"
  ]

  static func title(for date: Date) -> String? {
    var gregorian = Calendar(identifier: .gregorian)
    gregorian.timeZone = .autoupdatingCurrent
    let solar = gregorian.dateComponents([.year, .month, .day], from: date)

    if let month = solar.month,
       let day = solar.day,
       let title = solarFestivals[month * 100 + day] {
      return title
    }

    if let year = solar.year,
       solar.month == 4,
       solar.day == qingmingDay(in: year) {
      return "清明节"
    }

    var chinese = Calendar(identifier: .chinese)
    chinese.timeZone = .autoupdatingCurrent
    let lunar = chinese.dateComponents([.month, .day, .isLeapMonth], from: date)

    if lunar.isLeapMonth != true,
       let month = lunar.month,
       let day = lunar.day,
       let title = lunarFestivals[month * 100 + day] {
      return title
    }

    guard let tomorrow = gregorian.date(byAdding: .day, value: 1, to: date) else {
      return nil
    }
    let nextLunar = chinese.dateComponents([.month, .day, .isLeapMonth], from: tomorrow)
    if nextLunar.isLeapMonth != true, nextLunar.month == 1, nextLunar.day == 1 {
      return "除夕"
    }

    return nil
  }

  /// Common 21st-century Qingming approximation. The 2008 solar term is the
  /// one exceptional year in this range and falls a day earlier.
  private static func qingmingDay(in year: Int) -> Int? {
    guard (2000...2099).contains(year) else { return nil }
    let shortYear = year % 100
    let correction = year == 2008 ? 1 : 0
    return Int(Double(shortYear) * 0.2422 + 4.81)
      - Int(Double(shortYear - 1) / 4)
      - correction
  }
}
