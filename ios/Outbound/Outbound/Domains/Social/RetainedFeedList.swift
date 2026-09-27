import SwiftUI
import UIKit

/// UIKit owns the viewport and measured cell layout for the lifetime of this
/// feed. SwiftUI updates cell content only when its model actually changes.
struct RetainedFeedList<Row: Identifiable & Equatable, Content: View>: UIViewControllerRepresentable {
    let rows: [Row]
    let renderVersion: String
    let refresh: () async -> Void
    @ViewBuilder let content: (Row) -> Content

    func makeUIViewController(context: Context) -> Controller {
        Controller()
    }

    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.update(
            rows: rows,
            renderVersion: renderVersion,
            environment: context.environment,
            refresh: refresh,
            content: content
        )
    }

    final class Controller: UIViewController {
        private var collectionView: UICollectionView!
        private var dataSource: UICollectionViewDiffableDataSource<Int, Row.ID>!
        private var models: [Row.ID: Row] = [:]
        private var orderedIDs: [Row.ID] = []
        private var renderVersion = ""
        private var environment = EnvironmentValues()
        private var render: ((Row) -> Content)?
        private var refresh: (() async -> Void)?
        private let refreshControl = UIRefreshControl()
        private var refreshTask: Task<Void, Never>?

        override func loadView() {
            let item = NSCollectionLayoutItem(layoutSize: NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1), heightDimension: .estimated(600)
            ))
            let group = NSCollectionLayoutGroup.vertical(
                layoutSize: item.layoutSize, subitems: [item]
            )
            let section = NSCollectionLayoutSection(group: group)
            section.interGroupSpacing = 12
            section.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 0, bottom: 12, trailing: 0)
            collectionView = UICollectionView(
                frame: .zero, collectionViewLayout: UICollectionViewCompositionalLayout(section: section)
            )
            collectionView.backgroundColor = .clear
            collectionView.alwaysBounceVertical = true
            collectionView.allowsSelection = false
            // The SwiftUI parent already positions this view below the sticky
            // feature bar. Avoid a second navigation-bar inset adjustment.
            collectionView.contentInsetAdjustmentBehavior = .never
            collectionView.register(UICollectionViewCell.self, forCellWithReuseIdentifier: "feed")
            collectionView.refreshControl = refreshControl
            refreshControl.addTarget(self, action: #selector(refreshRequested), for: .valueChanged)
            view = collectionView
            dataSource = UICollectionViewDiffableDataSource<Int, Row.ID>(collectionView: collectionView) { [weak self] collection, indexPath, id in
                guard let self, let model = self.models[id], let render = self.render else { return nil }
                let cell = collection.dequeueReusableCell(withReuseIdentifier: "feed", for: indexPath)
                let environment = self.environment
                cell.contentConfiguration = UIHostingConfiguration {
                    render(model)
                        .id(model.id)
                        .environment(\.self, environment)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .margins(.all, 0)
                .minSize(width: 0, height: 0)
                return cell
            }
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            guard view.window != nil, view.bounds.height > 0 else { return }
            let bottomInset = view.safeAreaInsets.bottom
            if collectionView.contentInset.bottom != bottomInset {
                collectionView.contentInset.bottom = bottomInset
                collectionView.verticalScrollIndicatorInsets.bottom = bottomInset
            }
        }

        func update(
            rows: [Row],
            renderVersion: String,
            environment: EnvironmentValues,
            refresh: @escaping () async -> Void,
            content: @escaping (Row) -> Content
        ) {
            self.environment = environment
            self.refresh = refresh
            render = content
            loadViewIfNeeded()
            let ids = rows.map(\.id)
            let rerender = self.renderVersion != renderVersion
            let changed = rows.compactMap { row -> Row.ID? in
                guard let previous = models[row.id] else { return nil }
                return rerender || previous != row ? row.id : nil
            }
            // Navigation state and foreground notifications can re-evaluate
            // SocialHome without changing any row. Leave UIKit entirely alone.
            guard ids != orderedIDs || !changed.isEmpty else { return }
            models = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) })
            orderedIDs = ids
            self.renderVersion = renderVersion
            var snapshot = NSDiffableDataSourceSnapshot<Int, Row.ID>()
            snapshot.appendSections([0])
            snapshot.appendItems(ids)
            snapshot.reconfigureItems(changed)
            dataSource.apply(snapshot, animatingDifferences: false)
        }

        @objc private func refreshRequested() {
            guard refreshTask == nil, let refresh else { return }
            refreshTask = Task { [weak self] in
                await refresh()
                self?.refreshControl.endRefreshing()
                self?.refreshTask = nil
            }
        }
    }
}
