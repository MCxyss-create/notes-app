import SwiftData
import SwiftUI

extension EventType {
    /// Точки в сетке: ДР — розовая, праздник — красная, годовщина и другое — синяя.
    var color: Color {
        switch self {
        case .birthday: return .pink
        case .holiday: return .red
        case .anniversary, .other: return .blue
        }
    }
}

/// Открыть день: события дня и «Добавить на этот день».
struct DayRequest: Identifiable {
    let id = UUID()
    let date: Date
}

/// Вкладка «Календарь»: месяц с точками, «Ближайшие» на 30 дней, праздники и Контакты.
struct CalendarView: View {
    /// Демо-снимок: сразу открыть форму первого дня рождения.
    var demoEvent = false

    @Environment(\.calendar) private var calendar
    @Environment(\.modelContext) private var context
    @Query(sort: \CalendarEvent.createdAt) private var events: [CalendarEvent]
    @AppStorage(SettingsKeys.holidaysOn) private var holidaysOn = true
    @AppStorage(SettingsKeys.holidayReminders) private var holidayReminders = false
    @AppStorage(SettingsKeys.hiddenHolidays) private var hiddenText = ""
    @State private var shownMonth = Date()
    @State private var dayRequest: DayRequest?
    @State private var editing: EventEditRequest?
    @State private var importing = false
    @State private var importMessage: String?

    /// Свои события и праздники (если включены и не скрыты).
    private var entries: [CalendarEntry] {
        let own = events.map(\.entry)
        guard holidaysOn else { return own }
        return own + RussianHolidays.entries(hidden: RussianHolidays.hidden(from: hiddenText))
    }

    var body: some View {
        let all = entries
        List {
            Section {
                monthHeader
                weekdayRow
                grid(all)
            }

            Section("Ближайшие") {
                let soon = CalendarMath.upcoming(all, from: Date(), days: 30, calendar: calendar)
                if soon.isEmpty {
                    Text("На 30 дней ничего нет. Тапни по дню, чтобы добавить.")
                        .foregroundStyle(Color.secondary)
                } else {
                    ForEach(soon) { occurrence in
                        upcomingRow(occurrence)
                    }
                }
            }

            contactsAndHolidays
        }
        .listStyle(.insetGrouped)
        .sheet(item: $dayRequest) { request in
            DayEventsView(date: request.date)
        }
        .sheet(item: $editing) { request in
            NavigationStack {
                EventEditView(request: request)
            }
        }
        .task {
            guard demoEvent else { return }
            try? await Task.sleep(nanoseconds: 600_000_000)
            if let first = events.first(where: { $0.type == .birthday && $0.year != nil }) ?? events.first {
                editing = .edit(first)
            }
        }
    }

    // MARK: - Месяц

    private var monthParts: (year: Int, month: Int) {
        let parts = calendar.dateComponents([.year, .month], from: shownMonth)
        return (parts.year ?? 2026, parts.month ?? 1)
    }

    private var isCurrentMonth: Bool {
        calendar.isDate(shownMonth, equalTo: Date(), toGranularity: .month)
    }

    private var monthHeader: some View {
        HStack(spacing: 12) {
            Button {
                move(-1)
            } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 32, height: 32)
            }
            .accessibilityLabel("Прошлый месяц")

            Text("\(CalendarMath.monthsNominative[monthParts.month - 1]) \(String(monthParts.year))")
                .font(.headline)
                .frame(minWidth: 130)

            Button {
                move(1)
            } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 32, height: 32)
            }
            .accessibilityLabel("Следующий месяц")

            Spacer(minLength: 4)

            if !isCurrentMonth {
                Button("Сегодня") {
                    withAnimation { shownMonth = Date() }
                }
                .font(.subheadline.weight(.semibold))
            }
        }
        .buttonStyle(.borderless)
    }

    private var weekdayRow: some View {
        let symbols = calendar.shortStandaloneWeekdaySymbols
        let first = max(0, calendar.firstWeekday - 1)
        let ordered = Array(symbols[first...] + symbols[..<first])
        return HStack(spacing: 0) {
            ForEach(Array(ordered.enumerated()), id: \.offset) { _, symbol in
                Text(symbol.lowercased())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func grid(_ all: [CalendarEntry]) -> some View {
        let cells = CalendarMath.monthGrid(year: monthParts.year, month: monthParts.month, calendar: calendar)
        let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
        return LazyVGrid(columns: columns, spacing: 6) {
            ForEach(Array(cells.enumerated()), id: \.offset) { _, cell in
                if let date = cell {
                    dayCell(date, entries: CalendarMath.entries(on: date, in: all, calendar: calendar))
                } else {
                    Color.clear.frame(height: 44)
                }
            }
        }
        .padding(.vertical, 4)
        // Листается свайпом влево-вправо; вертикальную прокрутку не мешаем.
        .simultaneousGesture(
            DragGesture(minimumDistance: 30).onEnded { value in
                let dx = value.translation.width
                guard abs(dx) > 50, abs(dx) > abs(value.translation.height) * 1.5 else { return }
                move(dx < 0 ? 1 : -1)
            }
        )
    }

    private func dayCell(_ date: Date, entries: [CalendarEntry]) -> some View {
        let isToday = calendar.isDateInToday(date)
        var colors: [Color] = []
        for type in [EventType.birthday, .holiday, .anniversary, .other] where entries.contains(where: { $0.type == type }) {
            if !colors.contains(type.color) {
                colors.append(type.color)
            }
        }
        return VStack(spacing: 3) {
            Text("\(calendar.component(.day, from: date))")
                .font(.callout.weight(isToday ? .bold : .regular))
                .foregroundStyle(isToday ? Color.white : Color.primary)
                .frame(width: 30, height: 30)
                .background(isToday ? Color.accentColor : Color.clear, in: Circle())
            HStack(spacing: 3) {
                ForEach(colors.prefix(3), id: \.self) { color in
                    Circle()
                        .fill(color)
                        .frame(width: 6, height: 6)
                }
            }
            .frame(height: 6)
        }
        .frame(maxWidth: .infinity, minHeight: 44)
        .contentShape(Rectangle())
        .onTapGesture {
            dayRequest = DayRequest(date: date)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(calendar.component(.day, from: date)), событий: \(entries.count)")
        .accessibilityAddTraits(.isButton)
    }

    private func move(_ months: Int) {
        guard let moved = calendar.date(byAdding: .month, value: months, to: shownMonth) else { return }
        withAnimation(.easeInOut(duration: 0.2)) { shownMonth = moved }
    }

    // MARK: - Ближайшие

    /// «🎂 Лёша» / «Завтра · 1 ноября · исполнится 18».
    private func upcomingRow(_ occurrence: Occurrence) -> some View {
        let entry = occurrence.entry
        let isToday = calendar.isDateInToday(occurrence.date)
        var details = [CalendarMath.whenText(occurrence.date, from: Date(), calendar: calendar),
                       CalendarMath.dayMonthText(month: calendar.component(.month, from: occurrence.date),
                                                 day: calendar.component(.day, from: occurrence.date))]
        if let age = CalendarMath.ageText(entry.type, years: occurrence.years, isToday: isToday) {
            details.append(age)
        }
        return HStack(spacing: 12) {
            Image(systemName: entry.type.symbol)
                .foregroundStyle(entry.type.color)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(CalendarMath.label(entry))
                Text(details.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(isToday ? Color.accentColor : Color.secondary)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            dayRequest = DayRequest(date: occurrence.date)
        }
    }

    // MARK: - Праздники и Контакты

    private var contactsAndHolidays: some View {
        Section {
            Button {
                Task {
                    importing = true
                    importMessage = await ContactsImport.run(context: context)
                    importing = false
                }
            } label: {
                HStack {
                    Label("Дни рождения из Контактов", systemImage: "person.crop.circle.badge.plus")
                    Spacer()
                    if importing {
                        ProgressView()
                    }
                }
            }
            .disabled(importing)
            if let importMessage {
                Text(importMessage)
                    .font(.footnote)
                    .foregroundStyle(Color.secondary)
            }

            Toggle("Праздники РФ", isOn: $holidaysOn)
            if holidaysOn {
                Toggle("Напоминать о праздниках", isOn: $holidayReminders)
                let hidden = RussianHolidays.hidden(from: hiddenText)
                if !hidden.isEmpty {
                    Button("Вернуть скрытые праздники (\(hidden.count))") {
                        hiddenText = ""
                    }
                }
            }
        } header: {
            Text("Праздники и Контакты")
        } footer: {
            Text("Праздники появляются сами. Скрыть один — тапни по дню и смахни праздник влево. Контакты остаются на телефоне.")
        }
    }
}

/// События одного дня: свои — открыть и поправить, праздник — скрыть свайпом. Ниже — «Добавить на этот день».
struct DayEventsView: View {
    let date: Date

    @Environment(\.dismiss) private var dismiss
    @Environment(\.calendar) private var calendar
    @Query(sort: \CalendarEvent.createdAt) private var events: [CalendarEvent]
    @AppStorage(SettingsKeys.holidaysOn) private var holidaysOn = true
    @AppStorage(SettingsKeys.hiddenHolidays) private var hiddenText = ""

    private var dayEntries: [CalendarEntry] {
        var all = events.map(\.entry)
        if holidaysOn {
            all += RussianHolidays.entries(hidden: RussianHolidays.hidden(from: hiddenText))
        }
        return CalendarMath.entries(on: date, in: all, calendar: calendar)
    }

    private var title: String {
        CalendarMath.dayMonthText(month: calendar.component(.month, from: date), day: calendar.component(.day, from: date))
    }

    var body: some View {
        NavigationStack {
            List {
                let list = dayEntries
                Section {
                    if list.isEmpty {
                        Text("В этот день ничего нет")
                            .foregroundStyle(Color.secondary)
                    }
                    ForEach(list) { entry in
                        if let event = events.first(where: { $0.uid.uuidString == entry.id }) {
                            NavigationLink {
                                EventEditView(request: .edit(event))
                            } label: {
                                row(entry)
                            }
                        } else {
                            row(entry)
                                .swipeActions(edge: .trailing) {
                                    Button("Скрыть") {
                                        hide(entry)
                                    }
                                    .tint(.gray)
                                }
                        }
                    }
                }

                Section {
                    NavigationLink {
                        EventEditView(request: .new(month: calendar.component(.month, from: date),
                                                    day: calendar.component(.day, from: date)))
                    } label: {
                        Label("Добавить на этот день", systemImage: "plus")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }
                }
            }
        }
    }

    private func row(_ entry: CalendarEntry) -> some View {
        let years = CalendarMath.years(entry, on: date, calendar: calendar)
        let isToday = calendar.isDateInToday(date) || date < Date()
        var details = [entry.type.title]
        if let age = CalendarMath.ageText(entry.type, years: years, isToday: isToday) {
            details.append(age)
        }
        if entry.unofficial {
            details.append("неофициальный")
        }
        return HStack(spacing: 12) {
            Image(systemName: entry.type.symbol)
                .foregroundStyle(entry.type.color)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title)
                Text(details.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(Color.secondary)
            }
        }
    }

    private func hide(_ entry: CalendarEntry) {
        guard let id = RussianHolidays.holidayID(fromEntryID: entry.id) else { return }
        var hidden = RussianHolidays.hidden(from: hiddenText)
        hidden.insert(id)
        hiddenText = RussianHolidays.text(from: hidden)
    }
}
