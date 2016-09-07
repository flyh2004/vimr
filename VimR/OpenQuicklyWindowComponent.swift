/**
 * Tae Won Ha - http://taewon.de - @hataewon
 * See LICENSE
 */

import Cocoa
import PureLayout
import RxSwift
import RxCocoa

class OpenQuicklyWindowComponent: WindowComponent, NSWindowDelegate, NSTableViewDelegate, NSTableViewDataSource {

  let scanCondition = NSCondition()
  var pauseScan = false

  private(set) var pattern = ""
  private(set) var cwd = NSURL(fileURLWithPath: NSHomeDirectory(), isDirectory: true) {
    didSet {
      self.cwdPathCompsCount = self.cwd.pathComponents!.count
      self.cwdControl.URL = self.cwd
    }
  }
  private(set) var flatFileItems = [FileItem]()
  private(set) var fileViewItems = [ScoredFileItem]()

  private let userInitiatedScheduler = ConcurrentDispatchQueueScheduler(globalConcurrentQueueQOS: .UserInitiated)
  
  private let searchField = NSTextField(forAutoLayout: ())
  private let progressIndicator = NSProgressIndicator(forAutoLayout: ())
  private let cwdControl = NSPathControl(forAutoLayout: ())
  private let countField = NSTextField(forAutoLayout: ())
  private let fileView = NSTableView.standardSourceListTableView()
  
  private let fileItemService: FileItemService

  private var count = 0
  private var perSessionDisposeBag = DisposeBag()

  private var cwdPathCompsCount = 0
  private let searchStream: Observable<String>
  private let filterOpQueue = NSOperationQueue()

  init(source: Observable<Any>, fileItemService: FileItemService) {
    self.fileItemService = fileItemService
    self.searchStream = self.searchField.rx_text
      .throttle(0.2, scheduler: MainScheduler.instance)
      .distinctUntilChanged()
    
    super.init(source: source, nibName: "OpenQuicklyWindow")

    self.window.delegate = self
    self.filterOpQueue.qualityOfService = .UserInitiated
    self.filterOpQueue.name = "open-quickly-filter-operation-queue"
  }

  override func addViews() {
    let searchField = self.searchField
    let progressIndicator = self.progressIndicator
    progressIndicator.indeterminate = true
    progressIndicator.displayedWhenStopped = false
    progressIndicator.style = .SpinningStyle
    progressIndicator.controlSize = .SmallControlSize

    let fileView = self.fileView
    fileView.intercellSpacing = CGSize(width: 4, height: 4)
    fileView.setDataSource(self)
    fileView.setDelegate(self)
    
    let fileScrollView = NSScrollView.standardScrollView()
    fileScrollView.autoresizesSubviews = true
    fileScrollView.documentView = fileView

    let cwdControl = self.cwdControl
    cwdControl.pathStyle = .Standard
    cwdControl.backgroundColor = NSColor.clearColor()
    cwdControl.refusesFirstResponder = true
    cwdControl.cell?.controlSize = .SmallControlSize
    cwdControl.cell?.font = NSFont.systemFontOfSize(NSFont.smallSystemFontSize())
    cwdControl.setContentCompressionResistancePriority(NSLayoutPriorityDefaultLow, forOrientation:.Horizontal)

    let countField = self.countField
    countField.editable = false
    countField.bordered = false
    countField.alignment = .Right
    countField.backgroundColor = NSColor.clearColor()
    countField.stringValue = "0 items"

    let contentView = self.window.contentView!
    contentView.addSubview(searchField)
    contentView.addSubview(progressIndicator)
    contentView.addSubview(fileScrollView)
    contentView.addSubview(cwdControl)
    contentView.addSubview(countField)

    searchField.autoPinEdgeToSuperviewEdge(.Top, withInset: 18)
    searchField.autoPinEdgeToSuperviewEdge(.Right, withInset: 18)
    searchField.autoPinEdgeToSuperviewEdge(.Left, withInset: 18)

    progressIndicator.autoAlignAxis(.Horizontal, toSameAxisOfView: searchField)
    progressIndicator.autoPinEdge(.Right, toEdge: .Right, ofView: searchField, withOffset: -4)

    fileScrollView.autoPinEdge(.Top, toEdge: .Bottom, ofView: searchField, withOffset: 18)
    fileScrollView.autoPinEdge(.Right, toEdge: .Right, ofView: searchField)
    fileScrollView.autoPinEdge(.Left, toEdge: .Left, ofView: searchField)
    fileScrollView.autoSetDimension(.Height, toSize: 300)

    cwdControl.autoPinEdge(.Top, toEdge: .Bottom, ofView: fileScrollView, withOffset: 18)
    cwdControl.autoPinEdgeToSuperviewEdge(.Left, withInset: 18)
    cwdControl.autoPinEdgeToSuperviewEdge(.Bottom, withInset: 18)

    countField.autoPinEdge(.Top, toEdge: .Bottom, ofView: fileScrollView, withOffset: 18)
    countField.autoPinEdgeToSuperviewEdge(.Right, withInset: 18)
    countField.autoPinEdge(.Left, toEdge: .Right, ofView: cwdControl)
  }

  override func subscription(source source: Observable<Any>) -> Disposable {
    return NopDisposable.instance
  }

  func reloadFileView(withScoredItems items: [ScoredFileItem]) {
    self.fileViewItems = items
    self.fileView.reloadData()
  }

  func startProgress() {
    self.progressIndicator.startAnimation(self)
  }

  func endProgress() {
    self.progressIndicator.stopAnimation(self)
  }
  
  func show(forMainWindow mainWindow: MainWindowComponent) {
    self.cwd = mainWindow.cwd
    let flatFiles = self.fileItemService.flatFileItems(ofUrl: self.cwd)
      .subscribeOn(self.userInitiatedScheduler)

    self.searchStream
      .subscribe(onNext: { [unowned self] pattern in
        self.pattern = pattern
        self.resetAndAddFilterOperation()
        })
      .addDisposableTo(self.perSessionDisposeBag)

    flatFiles
      .subscribeOn(self.userInitiatedScheduler)
      .doOnNext{ [unowned self] items in
        self.scanCondition.lock()
        while self.pauseScan {
          self.scanCondition.wait()
        }
        self.scanCondition.unlock()

        self.flatFileItems.appendContentsOf(items)
        self.resetAndAddFilterOperation()
      }
      .observeOn(MainScheduler.instance)
      .subscribe(onNext: { [unowned self] items in
        self.count += items.count
        self.countField.stringValue = "\(self.count) items"
        })
      .addDisposableTo(self.perSessionDisposeBag)

    self.show()
    self.searchField.becomeFirstResponder()
  }

  private func resetAndAddFilterOperation() {
    self.filterOpQueue.cancelAllOperations()
    let op = OpenQuicklyFilterOperation(forOpenQuicklyWindow: self)
    self.filterOpQueue.addOperation(op)
  }
}

// MARK: - NSTableViewDataSource
extension OpenQuicklyWindowComponent {

  func numberOfRowsInTableView(_: NSTableView) -> Int {
    return self.fileViewItems.count
  }

  func tableView(tableView: NSTableView, viewForTableColumn _: NSTableColumn?, row: Int) -> NSView? {
    let cachedCell = tableView.makeViewWithIdentifier("file-view-row", owner: self)
    let cell = cachedCell as? ImageAndTextTableCell ?? ImageAndTextTableCell(withIdentifier: "file-view-row")

    let url = self.fileViewItems[row].url
    cell.text = self.rowText(forUrl: url)
    cell.image = self.fileItemService.icon(forUrl: url)
    
    return cell
  }

  private func rowText(forUrl url: NSURL) -> NSAttributedString {
    let pathComps = url.pathComponents!
    let truncatedPathComps = pathComps[self.cwdPathCompsCount..<pathComps.count]
    let name = truncatedPathComps.last!

    if truncatedPathComps.dropLast().isEmpty {
      return NSMutableAttributedString(string: name)
    }

    let rowText: NSMutableAttributedString
    let pathInfo = truncatedPathComps.dropLast().reverse().joinWithSeparator(" / ")
    rowText = NSMutableAttributedString(string: "\(name) — \(pathInfo)")
    rowText.addAttribute(NSForegroundColorAttributeName,
                         value: NSColor.lightGrayColor(),
                         range: NSRange(location:name.characters.count,
                         length: pathInfo.characters.count + 3))

    return rowText
  }
}

// MARK: - NSTableViewDelegate
extension OpenQuicklyWindowComponent {

  func tableViewSelectionDidChange(_: NSNotification) {
//    NSLog("\(#function): selection changed")
  }
}

// MARK: - NSWindowDelegate
extension OpenQuicklyWindowComponent {

  func windowWillClose(notification: NSNotification) {
    self.filterOpQueue.cancelAllOperations()

    self.endProgress()

    self.perSessionDisposeBag = DisposeBag()
    self.pauseScan = false
    self.count = 0

    self.pattern = ""
    self.flatFileItems = []
    self.fileViewItems = []
    
    self.searchField.stringValue = ""
    self.countField.stringValue = "0 items"
  }
}