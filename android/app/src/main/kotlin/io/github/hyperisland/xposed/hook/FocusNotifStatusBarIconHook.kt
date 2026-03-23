package io.github.hyperisland.xposed.hook

import android.app.Notification
import android.os.Bundle
import android.os.SystemClock
import android.view.View
import de.robv.android.xposed.IXposedHookLoadPackage
import de.robv.android.xposed.XC_MethodHook
import de.robv.android.xposed.XposedBridge
import de.robv.android.xposed.XposedHelpers
import de.robv.android.xposed.callbacks.XC_LoadPackage
import kotlin.jvm.JvmStatic

/**
 * 定向保留 HyperIsland 代理焦点通知的状态栏左上角小图标。
 *
 * 作用域：com.android.systemui（系统界面）
 *
 * 为什么优先选 FocusedNotifPromptController.toggleNotificationIcons(boolean)，
 * 而不是直接重写 MiuiCollapsedStatusBarFragment.updateStatusBarVisibilities(...)：
 *   1. toggleNotificationIcons(true) 是 HyperOS 中最直接的“隐藏通知图标区”入口，
 *      优先拦这里侵入面最小。
 *   2. updateStatusBarVisibilities(...) 牵涉状态栏更多可见性计算，包含运营商、网络、时钟、
 *      图标动画等联动逻辑，直接改那里更容易误伤系统原生行为。
 *   3. 某些 HyperOS 版本即使放过 toggleNotificationIcons，仍会在
 *      MiuiCollapsedStatusBarFragment.hideNotificationIconArea(...) 或后续可见性刷新里再次隐藏图标区，
 *      所以这里只增加同样定向的兜底拦截，不去改更大范围的可见性总逻辑。
 *   4. 当前机型上仅放开图标区仍不足够，因为焦点通知会在 icon pipeline 中被当作 focus notification 过滤掉，
 *      所以还要在 ActiveNotificationModel 构建后，将 HyperIsland 代理通知的 isFocusNotification 改为 false。
 *
 * 识别策略：
 *   - 优先检查 Notification.extras["hyperisland_focus_proxy"] == true
 *   - 若主标记缺失，再兼容检查 hyperisland_generic_processed / hyperisland_processed
 *   - 对于当前 HyperOS 版本中 controller / fragment 上拿不到“当前焦点通知对象”的情况，
 *     再使用 HyperIsland 自己发出焦点通知时记录的短时活动窗口作为兜底依据
 *
 * 安全策略：
 *   - 反射失败、字段缺失、当前通知无法识别时，一律放行原逻辑。
 *   - 必须避免误伤系统原生或其他应用自己的焦点通知。
 */
class FocusNotifStatusBarIconHook : IXposedHookLoadPackage {

    companion object {
        private const val TAG = "HyperIsland[FocusStatusBarIcon]"
        private const val TARGET_PACKAGE = "com.android.systemui"
        private const val TARGET_CONTROLLER_CLASS =
            "com.android.systemui.statusbar.phone.FocusedNotifPromptController"
        private const val TARGET_FRAGMENT_CLASS =
            "com.android.systemui.statusbar.phone.MiuiCollapsedStatusBarFragment"
        private const val TARGET_BEAN_CLASS =
            "com.android.systemui.statusbar.phone.FocusedNotifPromptController\$FocusedNotifBean"
        private const val TARGET_ENTRY_CLASS =
            "com.android.systemui.statusbar.notification.collection.NotificationEntry"
        private const val TARGET_STORE_BUILDER_CLASS =
            "com.android.systemui.statusbar.notification.domain.interactor.ActiveNotificationsStoreBuilder"
        private const val VISIBILITY_MODEL_CLASS =
            "com.android.systemui.statusbar.phone.fragment.StatusBarVisibilityModel"

        @Volatile private var cachedFocusProxyShowing = false
        @Volatile private var cachedFocusPromptShowing = false
        @Volatile private var cachedDirectProxyActiveUntilElapsed = 0L

        @JvmStatic
        internal fun markDirectProxyPosted(timeoutSecs: Int) {
            val safeTimeoutSecs = timeoutSecs.coerceAtLeast(3)
            cachedDirectProxyActiveUntilElapsed =
                SystemClock.elapsedRealtime() + (safeTimeoutSecs * 1000L) + 3000L
            cachedFocusProxyShowing = true
            XposedBridge.log(
                "$TAG: markDirectProxyPosted | timeoutSecs=$timeoutSecs | activeUntil=$cachedDirectProxyActiveUntilElapsed"
            )
        }

        @JvmStatic
        internal fun clearDirectProxyPosted() {
            cachedDirectProxyActiveUntilElapsed = 0L
            cachedFocusProxyShowing = false
            cachedFocusPromptShowing = false
            XposedBridge.log("$TAG: clearDirectProxyPosted")
        }

        private fun isDirectProxyActive(): Boolean {
            return cachedDirectProxyActiveUntilElapsed > SystemClock.elapsedRealtime()
        }
    }

    override fun handleLoadPackage(lpparam: XC_LoadPackage.LoadPackageParam) {
        if (lpparam.packageName != TARGET_PACKAGE) return
        hookNotifyNotifBeanChanged(lpparam.classLoader)
        hookSetIsFocusedNotifPromptShowing(lpparam.classLoader)
        hookToggleNotificationIcons(lpparam.classLoader)
        hookHideNotificationIconArea(lpparam.classLoader)
        hookUpdateStatusBarVisibilities(lpparam.classLoader)
        hookActiveNotificationModel(lpparam.classLoader)
    }

    private fun hookActiveNotificationModel(classLoader: ClassLoader) {
        try {
            XposedHelpers.findAndHookMethod(
                TARGET_STORE_BUILDER_CLASS,
                classLoader,
                "toModel",
                XposedHelpers.findClass(TARGET_ENTRY_CLASS, classLoader),
                object : XC_MethodHook() {
                    override fun afterHookedMethod(param: MethodHookParam) {
                        val entry = param.args[0] ?: return
                        val model = param.result ?: return
                        val sbn = getObjectFieldOrNull(entry, "mSbn") ?: return
                        val notification = resolveNotificationFromSbnLike(sbn) ?: return
                        if (!isHyperIslandFocusProxy(notification.extras)) return

                        try {
                            XposedHelpers.setBooleanField(model, "isFocusNotification", false)
                            XposedBridge.log(
                                "$TAG: forced ActiveNotificationModel.isFocusNotification=false for HyperIsland proxy"
                            )
                        } catch (e: Throwable) {
                            XposedBridge.log(
                                "$TAG: failed to override ActiveNotificationModel.isFocusNotification — ${e.message}"
                            )
                        }
                    }
                }
            )
            XposedBridge.log("$TAG: hooked ActiveNotificationsStoreBuilder.toModel(NotificationEntry)")
        } catch (e: Throwable) {
            XposedBridge.log("$TAG: ActiveNotificationsStoreBuilder.toModel hook failed — ${e.message}")
        }
    }

    private fun hookNotifyNotifBeanChanged(classLoader: ClassLoader) {
        try {
            val beanClass = XposedHelpers.findClass(TARGET_BEAN_CLASS, classLoader)
            XposedHelpers.findAndHookMethod(
                TARGET_CONTROLLER_CLASS,
                classLoader,
                "notifyNotifBeanChanged",
                beanClass,
                Boolean::class.javaPrimitiveType!!,
                object : XC_MethodHook() {
                    override fun beforeHookedMethod(param: MethodHookParam) {
                        val bean = param.args[0]
                        val notification = resolveNotificationFromBean(bean)
                        val isFocusProxy = isHyperIslandFocusProxy(notification?.extras)
                        cachedFocusProxyShowing = isFocusProxy
                        XposedBridge.log(
                            "$TAG: notifyNotifBeanChanged cached | hasNotification=${notification != null} | hyperislandFocusProxy=$isFocusProxy"
                        )
                    }
                }
            )
            XposedBridge.log("$TAG: hooked FocusedNotifPromptController.notifyNotifBeanChanged(...)")
        } catch (e: Throwable) {
            XposedBridge.log("$TAG: notifyNotifBeanChanged hook failed — ${e.message}")
        }
    }

    private fun hookSetIsFocusedNotifPromptShowing(classLoader: ClassLoader) {
        try {
            XposedHelpers.findAndHookMethod(
                TARGET_CONTROLLER_CLASS,
                classLoader,
                "setIsFocusedNotifPromptShowing",
                Boolean::class.javaPrimitiveType!!,
                object : XC_MethodHook() {
                    override fun beforeHookedMethod(param: MethodHookParam) {
                        val showing = param.args[0] as? Boolean ?: return
                        cachedFocusPromptShowing = showing
                        if (!showing && !isDirectProxyActive()) {
                            cachedFocusProxyShowing = false
                        }
                        XposedBridge.log(
                            "$TAG: setIsFocusedNotifPromptShowing cached | showing=$showing | hyperislandFocusProxy=$cachedFocusProxyShowing"
                        )
                    }
                }
            )
            XposedBridge.log("$TAG: hooked FocusedNotifPromptController.setIsFocusedNotifPromptShowing(boolean)")
        } catch (e: Throwable) {
            XposedBridge.log("$TAG: setIsFocusedNotifPromptShowing hook failed — ${e.message}")
        }
    }

    private fun hookToggleNotificationIcons(classLoader: ClassLoader) {
        try {
            XposedHelpers.findAndHookMethod(
                TARGET_CONTROLLER_CLASS,
                classLoader,
                "toggleNotificationIcons",
                Boolean::class.javaPrimitiveType!!,
                object : XC_MethodHook() {
                    override fun beforeHookedMethod(param: MethodHookParam) {
                        val shouldHide = param.args[0] as? Boolean ?: return
                        if (!shouldHide) return

                        val notification = resolveCurrentFocusedNotification(param.thisObject)
                        val keepIcons = shouldKeepIcons(notification)

                        XposedBridge.log(
                            "$TAG: toggleNotificationIcons(true) intercepted | hasNotification=${notification != null} | keepIcons=$keepIcons | cachedProxy=$cachedFocusProxyShowing | cachedShowing=$cachedFocusPromptShowing"
                        )

                        if (keepIcons) {
                            param.args[0] = false
                            XposedBridge.log(
                                "$TAG: keep status bar notification icons visible via toggleNotificationIcons"
                            )
                        }
                    }
                }
            )
            XposedBridge.log("$TAG: hooked FocusedNotifPromptController.toggleNotificationIcons(boolean)")
        } catch (e: Throwable) {
            XposedBridge.log("$TAG: toggleNotificationIcons hook failed — ${e.message}")
        }
    }

    private fun hookHideNotificationIconArea(classLoader: ClassLoader) {
        try {
            XposedHelpers.findAndHookMethod(
                TARGET_FRAGMENT_CLASS,
                classLoader,
                "hideNotificationIconArea",
                Boolean::class.javaPrimitiveType!!,
                object : XC_MethodHook() {
                    override fun beforeHookedMethod(param: MethodHookParam) {
                        val fragment = param.thisObject
                        val notification = resolveFocusedNotificationFromFragment(fragment)
                        val keepIcons = shouldKeepIcons(notification)

                        XposedBridge.log(
                            "$TAG: hideNotificationIconArea intercepted | hasNotification=${notification != null} | keepIcons=$keepIcons | cachedProxy=$cachedFocusProxyShowing | cachedShowing=$cachedFocusPromptShowing"
                        )

                        if (!keepIcons) return

                        forceShowNotificationIconsModel(fragment)
                        restoreNotificationIconArea(fragment)
                        refreshNotificationIconArea(fragment)
                        param.result = null
                        XposedBridge.log(
                            "$TAG: keep status bar notification icons visible via hideNotificationIconArea fallback"
                        )
                    }
                }
            )
            XposedBridge.log("$TAG: hooked MiuiCollapsedStatusBarFragment.hideNotificationIconArea(boolean)")
        } catch (e: Throwable) {
            XposedBridge.log("$TAG: hideNotificationIconArea hook failed — ${e.message}")
        }
    }

    private fun hookUpdateStatusBarVisibilities(classLoader: ClassLoader) {
        try {
            XposedHelpers.findAndHookMethod(
                TARGET_FRAGMENT_CLASS,
                classLoader,
                "updateStatusBarVisibilities",
                Boolean::class.javaPrimitiveType!!,
                object : XC_MethodHook() {
                    override fun afterHookedMethod(param: MethodHookParam) {
                        val fragment = param.thisObject
                        val notification = resolveFocusedNotificationFromFragment(fragment)
                        val keepIcons = shouldKeepIcons(notification)

                        XposedBridge.log(
                            "$TAG: updateStatusBarVisibilities finished | hasNotification=${notification != null} | keepIcons=$keepIcons | cachedProxy=$cachedFocusProxyShowing | cachedShowing=$cachedFocusPromptShowing"
                        )

                        if (!keepIcons) return

                        forceShowNotificationIconsModel(fragment)
                        restoreNotificationIconArea(fragment)
                        refreshNotificationIconArea(fragment)
                        XposedBridge.log(
                            "$TAG: re-show notification icon area after updateStatusBarVisibilities"
                        )
                    }
                }
            )
            XposedBridge.log("$TAG: hooked MiuiCollapsedStatusBarFragment.updateStatusBarVisibilities(boolean)")
        } catch (e: Throwable) {
            XposedBridge.log("$TAG: updateStatusBarVisibilities hook failed — ${e.message}")
        }
    }

    private fun shouldKeepIcons(notification: Notification?): Boolean {
        if (isHyperIslandFocusProxy(notification?.extras)) return true
        if (cachedFocusProxyShowing && cachedFocusPromptShowing) return true
        return isDirectProxyActive()
    }

    private fun forceShowNotificationIconsModel(fragment: Any?) {
        if (fragment == null) return
        try {
            val oldModel = getObjectFieldOrNull(fragment, "mLastModifiedVisibility") ?: return
            val modelClass = XposedHelpers.findClass(VISIBILITY_MODEL_CLASS, fragment.javaClass.classLoader)
            val newModel = XposedHelpers.newInstance(
                modelClass,
                XposedHelpers.getBooleanField(oldModel, "showClock"),
                true,
                XposedHelpers.getBooleanField(oldModel, "showPrimaryOngoingActivityChip"),
                XposedHelpers.getBooleanField(oldModel, "showSecondaryOngoingActivityChip"),
                XposedHelpers.getBooleanField(oldModel, "showSystemInfo"),
                XposedHelpers.getBooleanField(oldModel, "showNotifPromptView")
            )
            XposedHelpers.setObjectField(fragment, "mLastModifiedVisibility", newModel)
            XposedBridge.log("$TAG: forced StatusBarVisibilityModel.showNotificationIcons=true")
        } catch (e: Throwable) {
            XposedBridge.log("$TAG: forceShowNotificationIconsModel failed — ${e.message}")
        }
    }

    private fun refreshNotificationIconArea(fragment: Any?) {
        if (fragment == null) return
        try {
            XposedHelpers.callMethod(fragment, "updateNotificationIconAreaAndOngoingActivityChip", false)
            XposedBridge.log("$TAG: refreshed notification icon area")
        } catch (e: Throwable) {
            XposedBridge.log("$TAG: refreshNotificationIconArea failed — ${e.message}")
        }
    }

    private fun restoreNotificationIconArea(fragment: Any?) {
        if (fragment == null) return
        setVisible(getObjectFieldOrNull(fragment, "mNotificationIconAreaInner") as? View)
        setVisible(getObjectFieldOrNull(fragment, "mNotificationIcons") as? View)
        setVisible(getObjectFieldOrNull(fragment, "mStatusBarIcons") as? View)
        setVisible(getObjectFieldOrNull(fragment, "mStatusContainer") as? View)
    }

    private fun setVisible(view: View?) {
        if (view == null) return
        view.visibility = View.VISIBLE
        view.alpha = 1f
        view.translationX = 0f
    }

    /**
     * 不同 HyperOS 版本里 fragment 到 controller 的字段名可能变化，所以按 dep / controller 逐级探测。
     * 反射失败时必须放行，避免误伤系统原生焦点通知。
     */
    private fun resolveFocusedNotificationFromFragment(fragment: Any?): Notification? {
        if (fragment == null) return null
        val dep = getObjectFieldOrNull(fragment, "mDep") ?: return null
        val controller = listOfNotNull(
            getObjectFieldOrNull(dep, "focusedNotifPromptController"),
            getObjectFieldOrNull(dep, "mFocusedNotifPromptController")
        ).firstOrNull() ?: return null
        return resolveCurrentFocusedNotification(controller)
    }

    /**
     * 不同 HyperOS 版本里“当前焦点通知”挂载位置可能变化，所以按控制器常见字段逐级探测。
     * 先尝试 mCurrentNotifBean / mCurrentHeadUpNotifBean，再降级调用 getMaxPriorityBean()。
     * 反射失败时必须放行，避免误伤系统原生焦点通知。
     */
    private fun resolveCurrentFocusedNotification(controller: Any?): Notification? {
        if (controller == null) return null

        val beanCandidates = listOfNotNull(
            getObjectFieldOrNull(controller, "mCurrentNotifBean"),
            getObjectFieldOrNull(controller, "mCurrentHeadUpNotifBean"),
            callMethodOrNull(controller, "getMaxPriorityBean")
        )

        for (bean in beanCandidates) {
            resolveNotificationFromBean(bean)?.let { return it }
        }
        return null
    }

    /**
     * 不同 HyperOS 版本里 FocusedNotifBean 的字段名可能变化，所以从 bean / entry / sbn 逐级探测。
     * 优先走 bean.sbn，再尝试 bean.mEntry、bean.entry，必要时兼容 bean.notification。
     * 反射失败时必须放行，避免误伤系统原生焦点通知。
     */
    private fun resolveNotificationFromBean(bean: Any?): Notification? {
        if (bean == null) return null

        listOfNotNull(
            getObjectFieldOrNull(bean, "notification"),
            getObjectFieldOrNull(bean, "mNotification")
        ).firstNotNullOfOrNull { it as? Notification }?.let { return it }

        val sbnCandidates = listOfNotNull(
            getObjectFieldOrNull(bean, "sbn"),
            getObjectFieldOrNull(bean, "mSbn")
        )
        for (sbn in sbnCandidates) {
            resolveNotificationFromSbnLike(sbn)?.let { return it }
        }

        val entryCandidates = listOfNotNull(
            getObjectFieldOrNull(bean, "mEntry"),
            getObjectFieldOrNull(bean, "entry")
        )
        for (entry in entryCandidates) {
            resolveNotificationFromEntry(entry)?.let { return it }
        }

        return null
    }

    /**
     * 不同 HyperOS 版本里 NotificationEntry 的内部字段名可能变化，所以按 mSbn / sbn / getSbn() 逐级探测。
     * 找不到时必须保守返回 null，让系统继续执行自己的隐藏逻辑，避免误判非 HyperIsland 通知。
     */
    private fun resolveNotificationFromEntry(entry: Any?): Notification? {
        if (entry == null) return null

        val sbnCandidates = listOfNotNull(
            getObjectFieldOrNull(entry, "mSbn"),
            getObjectFieldOrNull(entry, "sbn"),
            callMethodOrNull(entry, "getSbn")
        )
        for (sbn in sbnCandidates) {
            resolveNotificationFromSbnLike(sbn)?.let { return it }
        }

        val notificationCandidates = listOfNotNull(
            getObjectFieldOrNull(entry, "mNotification"),
            getObjectFieldOrNull(entry, "notification"),
            callMethodOrNull(entry, "getNotification")
        )
        for (candidate in notificationCandidates) {
            (candidate as? Notification)?.let { return it }
            resolveNotificationFromSbnLike(candidate)?.let { return it }
        }

        return null
    }

    /**
     * 不同 HyperOS 版本里 sbn 具体类型可能是 StatusBarNotification、ExpandedNotification 或其包装对象，
     * 所以优先尝试 getNotification()，再兼容 notification / mNotification 字段逐级探测。
     * 若这一层仍失败，必须返回 null 并放行原逻辑，避免影响系统原生焦点通知。
     */
    private fun resolveNotificationFromSbnLike(sbn: Any?): Notification? {
        if (sbn == null) return null

        (callMethodOrNull(sbn, "getNotification") as? Notification)?.let { return it }
        (getObjectFieldOrNull(sbn, "notification") as? Notification)?.let { return it }
        (getObjectFieldOrNull(sbn, "mNotification") as? Notification)?.let { return it }

        return null
    }

    private fun isHyperIslandFocusProxy(extras: Bundle?): Boolean {
        if (extras == null) return false
        if (extras.getBoolean("hyperisland_focus_proxy", false)) return true
        if (extras.getBoolean("hyperisland_generic_processed", false)) return true
        if (extras.getBoolean("hyperisland_processed", false)) return true
        return false
    }

    /**
     * 字段名可能因 HyperOS 版本不同而变化，所以这里只尝试单个候选字段并把失败转为 null。
     * 上层会继续探测其他候选；反射失败时必须放行，避免误伤系统原生焦点通知。
     */
    private fun getObjectFieldOrNull(instance: Any, fieldName: String): Any? {
        return try {
            XposedHelpers.getObjectField(instance, fieldName)
        } catch (_: Throwable) {
            null
        }
    }

    /**
     * 方法名或可见性可能因 HyperOS 版本不同而变化，所以这里只做保守调用并把失败转为 null。
     * 上层会继续走其他探测路径；反射失败时必须放行，避免误伤系统原生焦点通知。
     */
    private fun callMethodOrNull(instance: Any, methodName: String): Any? {
        return try {
            XposedHelpers.callMethod(instance, methodName)
        } catch (_: Throwable) {
            null
        }
    }
}
