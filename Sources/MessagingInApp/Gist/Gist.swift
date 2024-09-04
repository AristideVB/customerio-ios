import CioInternalCommon
import Foundation
import UIKit

public class Gist: GistDelegate {
    private let logger: Logger
    var messageQueueManager = MessageQueueManager()
    var shownMessageQueueIds: Set<String> = []
    private var messageManagers: [MessageManager] = []
    public var siteId: String = ""
    public var dataCenter: String = ""

    public weak var delegate: GistDelegate?

    public static let shared = Gist()

    init() {
        self.logger = DIGraphShared.shared.logger
    }

    public func setup(
        siteId: String,
        dataCenter: String,
        logging: Bool = false,
        env: GistEnvironment = .production
    ) {
        self.siteId = siteId
        self.dataCenter = dataCenter
        messageQueueManager.setup()

        // Initialising Gist web with an empty message to fetch fonts and other assets.
        _ = Gist.shared.getMessageView(Message(messageId: ""))
    }

    // For testing to reset the singleton state
    func reset() {
        clearUserToken()
        messageQueueManager = MessageQueueManager()
        messageManagers = []
        // RouteManager.clearCurrentRoute()
    }

    public func resetState() {}

    public func setEventListener(_ eventListener: (any InAppEventListener)?) {}

    // MARK: User

    public func setUserToken(_ userToken: String) {
        // UserManager().setUserToken(userToken: userToken)
    }

    public func clearUserToken() {
        cancelModalMessage(ifDoesNotMatchRoute: "") // provide a new route to trigger a modal cancel.
        messageQueueManager.clearLocalStore()
        // UserManager().clearUserToken()
        messageQueueManager.clearUserMessagesFromLocalStore()
    }

    // MARK: Route

    public func getCurrentRoute() -> String {
        // RouteManager.getCurrentRoute()
        ""
    }

    public func setCurrentRoute(_ currentRoute: String) {
//        if RouteManager.getCurrentRoute() == currentRoute {
//            return // ignore request, route has not changed.
//        }

        cancelModalMessage(ifDoesNotMatchRoute: currentRoute)

        // RouteManager.setCurrentRoute(currentRoute)
        messageQueueManager.fetchUserMessagesFromLocalStore()
    }

    public func clearCurrentRoute() {
        // RouteManager.clearCurrentRoute()
    }

    // MARK: Message Actions

    public func showMessage(_ message: Message, position: MessagePosition = .center) -> Bool {
        if let messageManager = getModalMessageManager() {
            logger.info("Message cannot be displayed, \(messageManager.currentMessage.messageId) is being displayed.")
        } else {
            let messageManager = createMessageManager(siteId: siteId, message: message)
            messageManager.showMessage(position: position)
            return true
        }
        return false
    }

    public func getMessageView(_ message: Message) -> GistView {
        let messageManager = createMessageManager(siteId: siteId, message: message)
        return messageManager.getMessageView()
    }

    public func dismissMessage(instanceId: String? = nil, completionHandler: (() -> Void)? = nil) {
        if let id = instanceId, let messageManager = messageManager(instanceId: id) {
            messageManager.removePersistentMessage()
            messageManager.dismissMessage(completionHandler: completionHandler)
        } else {
            getModalMessageManager()?.dismissMessage(completionHandler: completionHandler)
        }
    }

    // MARK: Events

    public func messageShown(message: Message) {
        logger.debug("Message with route: \(message.messageId) shown")
        if message.gistProperties.persistent != true {
            logMessageView(message: message)
        } else {
            logger.debug("Persistent message shown, skipping logging view")
        }
        delegate?.messageShown(message: message)
    }

    public func messageDismissed(message: Message) {
        logger.debug("Message with id: \(message.messageId) dismissed")
        removeMessageManager(instanceId: message.instanceId)
        delegate?.messageDismissed(message: message)

        messageQueueManager.fetchUserMessagesFromLocalStore()
    }

    public func messageError(message: Message) {
        removeMessageManager(instanceId: message.instanceId)
        delegate?.messageError(message: message)
    }

    public func action(message: Message, currentRoute: String, action: String, name: String) {
        delegate?.action(message: message, currentRoute: currentRoute, action: action, name: name)
    }

    public func embedMessage(message: Message, elementId: String) {
        delegate?.embedMessage(message: message, elementId: elementId)
    }

    func logMessageView(message: Message) {
        messageQueueManager.removeMessageFromLocalStore(message: message)
        if let queueId = message.queueId {
            shownMessageQueueIds.insert(queueId)
        }
        let state = InAppMessageState()
        DIGraphShared.shared.logManager
            .logView(state: state, message: message) { response in
                if case .failure(let error) = response {
                    self.logger.error("Failed to log view for message: \(message.messageId) with error: \(error)")
                }
            }
    }

    // When the user navigates to a different screen, modal messages should only appear if they are meant for the current screen.
    // If the currently displayed/loading modal message has a page rule, it should not be shown anymore.
    private func cancelModalMessage(ifDoesNotMatchRoute newRoute: String) {
        if let messageManager = getModalMessageManager() {
            let modalMessageLoadingOrDisplayed = messageManager.currentMessage

            if modalMessageLoadingOrDisplayed.doesHavePageRule(), !modalMessageLoadingOrDisplayed.doesPageRuleMatch(route: newRoute) {
                // the page rule has changed and the currently loading/visible modal has page rules set, it should no longer be shown.
                logger.debug("Cancelled showing message with id: \(modalMessageLoadingOrDisplayed.messageId)")

                // Stop showing the current message synchronously meaning to remove from UI instantly.
                // We want to be sure the message is gone when this function returns and be ready to display another message if needed.
                messageManager.cancelShowingMessage()

                // Removing the message manager allows you to show a new modal message. Otherwise, request to show will be ignored.
                removeMessageManager(instanceId: modalMessageLoadingOrDisplayed.instanceId)
            }
        }
    }

    // Message Manager

    private func createMessageManager(siteId: String, message: Message) -> MessageManager {
        let messageManager = MessageManager(state: InAppMessageState(), message: message)
        messageManager.delegate = self
        messageManagers.append(messageManager)
        return messageManager
    }

    func getModalMessageManager() -> MessageManager? {
        messageManagers.first(where: { !$0.isMessageEmbed })
    }

    func messageManager(instanceId: String) -> MessageManager? {
        messageManagers.first(where: { $0.currentMessage.instanceId == instanceId })
    }

    func removeMessageManager(instanceId: String) {
        messageManagers.removeAll(where: { $0.currentMessage.instanceId == instanceId })
    }
}
