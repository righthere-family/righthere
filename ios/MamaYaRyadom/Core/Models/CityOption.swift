import Foundation

// MARK: - City

struct City: Identifiable, Hashable, Sendable {
    let ru: String
    let en: String
    let timezone: String

    var id: String { ru }

    var displayName: String {
        L10n.effectiveLanguage == "ru" ? ru : en
    }

    func matches(_ name: String) -> Bool {
        ru == name || en == name
    }

    static func search(_ query: String, limit: Int = 5) -> [City] {
        let needle = normalize(query)
        guard needle.count >= 2 else { return [] }
        let prefix = all.filter {
            normalize($0.ru).hasPrefix(needle) || normalize($0.en).hasPrefix(needle)
        }
        let contains = all.filter {
            (normalize($0.ru).contains(needle) || normalize($0.en).contains(needle))
                && !prefix.contains($0)
        }
        return Array((prefix + contains).prefix(limit))
    }

    private static func normalize(_ value: String) -> String {
        value.lowercased().replacingOccurrences(of: "ё", with: "е")
    }
}

// MARK: - Directory

extension City {
    static let all: [City] = [
        City(ru: "Москва", en: "Moscow", timezone: "Europe/Moscow"),
        City(ru: "Санкт-Петербург", en: "Saint Petersburg", timezone: "Europe/Moscow"),
        City(ru: "Казань", en: "Kazan", timezone: "Europe/Moscow"),
        City(ru: "Нижний Новгород", en: "Nizhny Novgorod", timezone: "Europe/Moscow"),
        City(ru: "Ростов-на-Дону", en: "Rostov-on-Don", timezone: "Europe/Moscow"),
        City(ru: "Краснодар", en: "Krasnodar", timezone: "Europe/Moscow"),
        City(ru: "Сочи", en: "Sochi", timezone: "Europe/Moscow"),
        City(ru: "Воронеж", en: "Voronezh", timezone: "Europe/Moscow"),
        City(ru: "Тула", en: "Tula", timezone: "Europe/Moscow"),
        City(ru: "Ярославль", en: "Yaroslavl", timezone: "Europe/Moscow"),
        City(ru: "Рязань", en: "Ryazan", timezone: "Europe/Moscow"),
        City(ru: "Липецк", en: "Lipetsk", timezone: "Europe/Moscow"),
        City(ru: "Пенза", en: "Penza", timezone: "Europe/Moscow"),
        City(ru: "Иваново", en: "Ivanovo", timezone: "Europe/Moscow"),
        City(ru: "Тверь", en: "Tver", timezone: "Europe/Moscow"),
        City(ru: "Брянск", en: "Bryansk", timezone: "Europe/Moscow"),
        City(ru: "Курск", en: "Kursk", timezone: "Europe/Moscow"),
        City(ru: "Белгород", en: "Belgorod", timezone: "Europe/Moscow"),
        City(ru: "Смоленск", en: "Smolensk", timezone: "Europe/Moscow"),
        City(ru: "Орёл", en: "Oryol", timezone: "Europe/Moscow"),
        City(ru: "Калуга", en: "Kaluga", timezone: "Europe/Moscow"),
        City(ru: "Владимир", en: "Vladimir", timezone: "Europe/Moscow"),
        City(ru: "Тамбов", en: "Tambov", timezone: "Europe/Moscow"),
        City(ru: "Кострома", en: "Kostroma", timezone: "Europe/Moscow"),
        City(ru: "Архангельск", en: "Arkhangelsk", timezone: "Europe/Moscow"),
        City(ru: "Мурманск", en: "Murmansk", timezone: "Europe/Moscow"),
        City(ru: "Петрозаводск", en: "Petrozavodsk", timezone: "Europe/Moscow"),
        City(ru: "Вологда", en: "Vologda", timezone: "Europe/Moscow"),
        City(ru: "Череповец", en: "Cherepovets", timezone: "Europe/Moscow"),
        City(ru: "Великий Новгород", en: "Veliky Novgorod", timezone: "Europe/Moscow"),
        City(ru: "Псков", en: "Pskov", timezone: "Europe/Moscow"),
        City(ru: "Ставрополь", en: "Stavropol", timezone: "Europe/Moscow"),
        City(ru: "Махачкала", en: "Makhachkala", timezone: "Europe/Moscow"),
        City(ru: "Грозный", en: "Grozny", timezone: "Europe/Moscow"),
        City(ru: "Владикавказ", en: "Vladikavkaz", timezone: "Europe/Moscow"),
        City(ru: "Нальчик", en: "Nalchik", timezone: "Europe/Moscow"),
        City(ru: "Симферополь", en: "Simferopol", timezone: "Europe/Simferopol"),
        City(ru: "Калининград", en: "Kaliningrad", timezone: "Europe/Kaliningrad"),
        City(ru: "Самара", en: "Samara", timezone: "Europe/Samara"),
        City(ru: "Тольятти", en: "Tolyatti", timezone: "Europe/Samara"),
        City(ru: "Ижевск", en: "Izhevsk", timezone: "Europe/Samara"),
        City(ru: "Ульяновск", en: "Ulyanovsk", timezone: "Europe/Ulyanovsk"),
        City(ru: "Астрахань", en: "Astrakhan", timezone: "Europe/Astrakhan"),
        City(ru: "Саратов", en: "Saratov", timezone: "Europe/Saratov"),
        City(ru: "Волгоград", en: "Volgograd", timezone: "Europe/Volgograd"),
        City(ru: "Киров", en: "Kirov", timezone: "Europe/Kirov"),
        City(ru: "Екатеринбург", en: "Yekaterinburg", timezone: "Asia/Yekaterinburg"),
        City(ru: "Челябинск", en: "Chelyabinsk", timezone: "Asia/Yekaterinburg"),
        City(ru: "Уфа", en: "Ufa", timezone: "Asia/Yekaterinburg"),
        City(ru: "Пермь", en: "Perm", timezone: "Asia/Yekaterinburg"),
        City(ru: "Тюмень", en: "Tyumen", timezone: "Asia/Yekaterinburg"),
        City(ru: "Магнитогорск", en: "Magnitogorsk", timezone: "Asia/Yekaterinburg"),
        City(ru: "Оренбург", en: "Orenburg", timezone: "Asia/Yekaterinburg"),
        City(ru: "Курган", en: "Kurgan", timezone: "Asia/Yekaterinburg"),
        City(ru: "Сургут", en: "Surgut", timezone: "Asia/Yekaterinburg"),
        City(ru: "Нижневартовск", en: "Nizhnevartovsk", timezone: "Asia/Yekaterinburg"),
        City(ru: "Омск", en: "Omsk", timezone: "Asia/Omsk"),
        City(ru: "Новосибирск", en: "Novosibirsk", timezone: "Asia/Novosibirsk"),
        City(ru: "Барнаул", en: "Barnaul", timezone: "Asia/Barnaul"),
        City(ru: "Томск", en: "Tomsk", timezone: "Asia/Tomsk"),
        City(ru: "Кемерово", en: "Kemerovo", timezone: "Asia/Novokuznetsk"),
        City(ru: "Новокузнецк", en: "Novokuznetsk", timezone: "Asia/Novokuznetsk"),
        City(ru: "Красноярск", en: "Krasnoyarsk", timezone: "Asia/Krasnoyarsk"),
        City(ru: "Абакан", en: "Abakan", timezone: "Asia/Krasnoyarsk"),
        City(ru: "Иркутск", en: "Irkutsk", timezone: "Asia/Irkutsk"),
        City(ru: "Улан-Удэ", en: "Ulan-Ude", timezone: "Asia/Irkutsk"),
        City(ru: "Чита", en: "Chita", timezone: "Asia/Chita"),
        City(ru: "Якутск", en: "Yakutsk", timezone: "Asia/Yakutsk"),
        City(ru: "Владивосток", en: "Vladivostok", timezone: "Asia/Vladivostok"),
        City(ru: "Хабаровск", en: "Khabarovsk", timezone: "Asia/Vladivostok"),
        City(ru: "Южно-Сахалинск", en: "Yuzhno-Sakhalinsk", timezone: "Asia/Sakhalin"),
        City(ru: "Магадан", en: "Magadan", timezone: "Asia/Magadan"),
        City(ru: "Петропавловск-Камчатский", en: "Petropavlovsk-Kamchatsky", timezone: "Asia/Kamchatka"),
        City(ru: "Алматы", en: "Almaty", timezone: "Asia/Almaty"),
        City(ru: "Астана", en: "Astana", timezone: "Asia/Almaty"),
        City(ru: "Шымкент", en: "Shymkent", timezone: "Asia/Almaty"),
        City(ru: "Караганда", en: "Karaganda", timezone: "Asia/Almaty"),
        City(ru: "Актобе", en: "Aktobe", timezone: "Asia/Aqtobe"),
        City(ru: "Атырау", en: "Atyrau", timezone: "Asia/Atyrau"),
        City(ru: "Уральск", en: "Oral", timezone: "Asia/Oral"),
        City(ru: "Минск", en: "Minsk", timezone: "Europe/Minsk"),
        City(ru: "Гомель", en: "Gomel", timezone: "Europe/Minsk"),
        City(ru: "Брест", en: "Brest", timezone: "Europe/Minsk"),
        City(ru: "Витебск", en: "Vitebsk", timezone: "Europe/Minsk"),
        City(ru: "Гродно", en: "Grodno", timezone: "Europe/Minsk"),
        City(ru: "Могилёв", en: "Mogilev", timezone: "Europe/Minsk"),
        City(ru: "Киев", en: "Kyiv", timezone: "Europe/Kyiv"),
        City(ru: "Харьков", en: "Kharkiv", timezone: "Europe/Kyiv"),
        City(ru: "Одесса", en: "Odesa", timezone: "Europe/Kyiv"),
        City(ru: "Днепр", en: "Dnipro", timezone: "Europe/Kyiv"),
        City(ru: "Львов", en: "Lviv", timezone: "Europe/Kyiv"),
        City(ru: "Запорожье", en: "Zaporizhzhia", timezone: "Europe/Kyiv"),
        City(ru: "Ереван", en: "Yerevan", timezone: "Asia/Yerevan"),
        City(ru: "Гюмри", en: "Gyumri", timezone: "Asia/Yerevan"),
        City(ru: "Тбилиси", en: "Tbilisi", timezone: "Asia/Tbilisi"),
        City(ru: "Батуми", en: "Batumi", timezone: "Asia/Tbilisi"),
        City(ru: "Кутаиси", en: "Kutaisi", timezone: "Asia/Tbilisi"),
        City(ru: "Баку", en: "Baku", timezone: "Asia/Baku"),
        City(ru: "Ташкент", en: "Tashkent", timezone: "Asia/Tashkent"),
        City(ru: "Самарканд", en: "Samarkand", timezone: "Asia/Samarkand"),
        City(ru: "Бишкек", en: "Bishkek", timezone: "Asia/Bishkek"),
        City(ru: "Душанбе", en: "Dushanbe", timezone: "Asia/Dushanbe"),
        City(ru: "Кишинёв", en: "Chisinau", timezone: "Europe/Chisinau"),
        City(ru: "Стамбул", en: "Istanbul", timezone: "Europe/Istanbul"),
        City(ru: "Анталья", en: "Antalya", timezone: "Europe/Istanbul"),
        City(ru: "Аланья", en: "Alanya", timezone: "Europe/Istanbul"),
        City(ru: "Измир", en: "Izmir", timezone: "Europe/Istanbul"),
        City(ru: "Белград", en: "Belgrade", timezone: "Europe/Belgrade"),
        City(ru: "Нови-Сад", en: "Novi Sad", timezone: "Europe/Belgrade"),
        City(ru: "Подгорица", en: "Podgorica", timezone: "Europe/Podgorica"),
        City(ru: "Будва", en: "Budva", timezone: "Europe/Podgorica"),
        City(ru: "Тель-Авив", en: "Tel Aviv", timezone: "Asia/Jerusalem"),
        City(ru: "Хайфа", en: "Haifa", timezone: "Asia/Jerusalem"),
        City(ru: "Иерусалим", en: "Jerusalem", timezone: "Asia/Jerusalem"),
        City(ru: "Лимассол", en: "Limassol", timezone: "Asia/Nicosia"),
        City(ru: "Никосия", en: "Nicosia", timezone: "Asia/Nicosia"),
        City(ru: "Берлин", en: "Berlin", timezone: "Europe/Berlin"),
        City(ru: "Мюнхен", en: "Munich", timezone: "Europe/Berlin"),
        City(ru: "Франкфурт", en: "Frankfurt", timezone: "Europe/Berlin"),
        City(ru: "Варшава", en: "Warsaw", timezone: "Europe/Warsaw"),
        City(ru: "Краков", en: "Krakow", timezone: "Europe/Warsaw"),
        City(ru: "Прага", en: "Prague", timezone: "Europe/Prague"),
        City(ru: "Вена", en: "Vienna", timezone: "Europe/Vienna"),
        City(ru: "Париж", en: "Paris", timezone: "Europe/Paris"),
        City(ru: "Амстердам", en: "Amsterdam", timezone: "Europe/Amsterdam"),
        City(ru: "Барселона", en: "Barcelona", timezone: "Europe/Madrid"),
        City(ru: "Мадрид", en: "Madrid", timezone: "Europe/Madrid"),
        City(ru: "Лиссабон", en: "Lisbon", timezone: "Europe/Lisbon"),
        City(ru: "Лондон", en: "London", timezone: "Europe/London"),
        City(ru: "Дубай", en: "Dubai", timezone: "Asia/Dubai"),
        City(ru: "Бангкок", en: "Bangkok", timezone: "Asia/Bangkok"),
        City(ru: "Паттайя", en: "Pattaya", timezone: "Asia/Bangkok"),
        City(ru: "Пхукет", en: "Phuket", timezone: "Asia/Bangkok"),
        City(ru: "Бали", en: "Bali", timezone: "Asia/Makassar"),
        City(ru: "Нью-Йорк", en: "New York", timezone: "America/New_York"),
        City(ru: "Майами", en: "Miami", timezone: "America/New_York"),
        City(ru: "Чикаго", en: "Chicago", timezone: "America/Chicago"),
        City(ru: "Лос-Анджелес", en: "Los Angeles", timezone: "America/Los_Angeles"),
        City(ru: "Сан-Франциско", en: "San Francisco", timezone: "America/Los_Angeles"),
        City(ru: "Торонто", en: "Toronto", timezone: "America/Toronto"),
        City(ru: "Сидней", en: "Sydney", timezone: "Australia/Sydney"),
    ]
}
