//
//  STBtnTestViewController.swift
//  STBaseProject_Example
//
//  Created by 寒江孤影 on 2026/4/27.
//

import UIKit
import STBaseProject

final class STBtnTestViewController: BaseViewController {

    private let scrollView = UIScrollView()
    private let stackView = UIStackView()
    private let verificationButton = STVerificationCodeBtn(type: .custom)

    override func viewDidLoad() {
        super.viewDidLoad()
        self.titleLabel.text = "STBtn 测试"
        self.setupScrollView()
        self.setupButtons()
    }

    private func setupScrollView() {
        self.scrollView.translatesAutoresizingMaskIntoConstraints = false
        self.view.addSubview(self.scrollView)
        NSLayoutConstraint.activate([
            self.scrollView.topAnchor.constraint(equalTo: self.view.topAnchor),
            self.scrollView.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            self.scrollView.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
            self.scrollView.bottomAnchor.constraint(equalTo: self.view.bottomAnchor)
        ])

        self.stackView.axis = .vertical
        self.stackView.spacing = 14
        self.stackView.translatesAutoresizingMaskIntoConstraints = false
        self.scrollView.addSubview(self.stackView)
        NSLayoutConstraint.activate([
            self.stackView.topAnchor.constraint(equalTo: self.scrollView.topAnchor, constant: STDeviceAdapter.navigationBarHeight + 20),
            self.stackView.leadingAnchor.constraint(equalTo: self.scrollView.leadingAnchor, constant: 20),
            self.stackView.trailingAnchor.constraint(equalTo: self.scrollView.trailingAnchor, constant: -20),
            self.stackView.bottomAnchor.constraint(equalTo: self.scrollView.bottomAnchor, constant: -24),
            self.stackView.widthAnchor.constraint(equalTo: self.scrollView.widthAnchor, constant: -40)
        ])
    }

    private func setupButtons() {
        self.addSectionLabel("基础样式")
        self.stackView.addArrangedSubview(self.makeNormalButton())
        self.stackView.addArrangedSubview(self.makeRoundedButton())
        self.stackView.addArrangedSubview(self.makeDisabledButton())

        self.addSectionLabel("内容边距")
        self.stackView.addArrangedSubview(self.makeLeftPaddingButton())
        self.stackView.addArrangedSubview(self.makeRightPaddingButton())

        self.addSectionLabel("背景样式")
        self.stackView.addArrangedSubview(self.makeGradientButton())
        self.stackView.addArrangedSubview(self.makeLiquidGlassButton())

        self.addSectionLabel("阴影与圆角")
        self.stackView.addArrangedSubview(self.makeShadowButton())

        self.addSectionLabel("交互反馈 · 点击变色")
        self.stackView.addArrangedSubview(self.makeHighlightColorButton())
        self.stackView.addArrangedSubview(self.makeHighlightColorRoundedButton())

        self.addSectionLabel("STIconBtn · 图文位置")
        self.stackView.addArrangedSubview(self.makeFilledIconButton(position: .left, title: "STIconBtn 左图右文"))
        self.stackView.addArrangedSubview(self.makeFilledIconButton(position: .right, title: "STIconBtn 右图左文"))
        self.stackView.addArrangedSubview(self.makeFilledIconButton(position: .top, title: "STIconBtn 上图下文"))

        self.addSectionLabel("STIconBtn · 自适应宽度")
        self.stackView.addArrangedSubview(self.makeAdaptiveIconButtonsRow())

        self.addSectionLabel("STVerificationCodeBtn · 倒计时")
        self.setupVerificationButton()
        self.stackView.addArrangedSubview(self.verificationButton)
    }

    private func addSectionLabel(_ title: String) {
        if !self.stackView.arrangedSubviews.isEmpty {
            let spacer = UIView()
            spacer.heightAnchor.constraint(equalToConstant: 8).isActive = true
            self.stackView.addArrangedSubview(spacer)
        }
        let label = UILabel()
        label.text = title
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.textColor = .secondaryLabel
        self.stackView.addArrangedSubview(label)
    }

    // MARK: - 基础样式
    private func makeNormalButton() -> STBtn {
        let button = self.makeBaseButton(title: "普通 STBtn")
        button.backgroundColor = .systemBlue
        button.setTitleColor(.white, for: .normal)
        return button
    }

    private func makeRoundedButton() -> STBtn {
        let button = self.makeBaseButton(title: "圆角 + 边框")
        button.backgroundColor = .secondarySystemGroupedBackground
        button.setTitleColor(.label, for: .normal)
        button.st_roundedButton(cornerRadius: 14, borderWidth: 1, borderColor: .systemBlue)
        return button
    }

    private func makeDisabledButton() -> STBtn {
        let button = self.makeBaseButton(title: "禁用态 STBtn")
        button.backgroundColor = .systemGray5
        button.setTitleColor(.secondaryLabel, for: .disabled)
        button.isEnabled = false
        return button
    }

    // MARK: - 内容边距
    private func makeLeftPaddingButton() -> STBtn {
        let button = self.makeBaseButton(title: "左对齐 + contentHorizontalPadding = 24")
        button.backgroundColor = .systemIndigo.withAlphaComponent(0.14)
        button.setTitleColor(.systemIndigo, for: .normal)
        button.contentHorizontalAlignment = .left
        button.contentHorizontalPadding = 24
        return button
    }

    private func makeRightPaddingButton() -> STBtn {
        let button = self.makeBaseButton(title: "右对齐 + contentHorizontalPadding = 24")
        button.backgroundColor = .systemTeal.withAlphaComponent(0.14)
        button.setTitleColor(.systemTeal, for: .normal)
        button.contentHorizontalAlignment = .right
        button.contentHorizontalPadding = 24
        return button
    }

    // MARK: - 背景样式
    private func makeGradientButton() -> STBtn {
        let button = self.makeBaseButton(title: "渐变背景")
        button.cornerRadius = 16
        button.clipsContentToBounds = true
        button.setTitleColor(.white, for: .normal)
        button.st_setGradientBackground(
            colors: [.systemPurple, .systemPink, .systemOrange],
            startPoint: CGPoint(x: 0, y: 0.5),
            endPoint: CGPoint(x: 1, y: 0.5)
        )
        return button
    }

    private func makeLiquidGlassButton() -> STBtn {
        let button = self.makeBaseButton(title: "Liquid Glass 背景")
        button.cornerRadius = 18
        button.setTitleColor(.label, for: .normal)
        button.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.12)
        button.st_setLiquidGlassBackground(
            tintColor: UIColor.white.withAlphaComponent(0.2),
            highlightOpacity: 0.5,
            borderColor: UIColor.white.withAlphaComponent(0.55)
        )
        button.st_setShadow(
            color: UIColor.black.withAlphaComponent(0.18),
            offset: CGSize(width: 0, height: 8),
            radius: 18,
            opacity: 1
        )
        return button
    }

    // MARK: - 阴影
    private func makeShadowButton() -> STBtn {
        let button = self.makeBaseButton(title: "阴影 + 圆角不裁剪")
        button.cornerRadius = 16
        button.backgroundColor = .secondarySystemGroupedBackground
        button.setTitleColor(.label, for: .normal)
        button.st_setShadow(
            color: UIColor.black.withAlphaComponent(0.16),
            offset: CGSize(width: 0, height: 6),
            radius: 14,
            opacity: 1
        )
        return button
    }

    private func makeBaseButton(title: String) -> STBtn {
        let button = STBtn(type: .custom)
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
        button.heightAnchor.constraint(equalToConstant: 52).isActive = true
        return button
    }

    // MARK: - 交互反馈：点击后背景颜色变化
    /// 通过覆写 `refineButtonConfiguration` 在每次 configuration update（含 `isHighlighted` 变化）
    /// 里重写 `config.background.backgroundColor`，避免外部设置 `configurationUpdateHandler` 覆盖
    /// `STBtn` 的基线重置逻辑。
    private final class STHighlightColorBtn: STBtn {
        var normalBackgroundColor: UIColor = .systemBlue {
            didSet { self.setNeedsUpdateConfiguration() }
        }
        var highlightedBackgroundColor: UIColor = .systemIndigo {
            didSet { self.setNeedsUpdateConfiguration() }
        }
        var disabledBackgroundColor: UIColor = .systemGray3 {
            didSet { self.setNeedsUpdateConfiguration() }
        }

        override func refineButtonConfiguration(_ button: UIButton, configuration config: inout UIButton.Configuration) {
            super.refineButtonConfiguration(button, configuration: &config)
            var background = config.background
            if !button.isEnabled {
                background.backgroundColor = self.disabledBackgroundColor
            } else if button.isHighlighted {
                background.backgroundColor = self.highlightedBackgroundColor
            } else {
                background.backgroundColor = self.normalBackgroundColor
            }
            config.background = background
        }
    }

    private func makeHighlightColorButton() -> STBtn {
        let button = STHighlightColorBtn(type: .custom)
        button.setTitle("按下查看背景色变化", for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
        button.setTitleColor(.white, for: .normal)
        button.setTitleColor(.white, for: .highlighted)
        button.normalBackgroundColor = .systemBlue
        button.highlightedBackgroundColor = .systemIndigo
        button.heightAnchor.constraint(equalToConstant: 52).isActive = true
        button.addTarget(self, action: #selector(self.onHighlightButtonTapped(_:)), for: .touchUpInside)
        return button
    }

    private func makeHighlightColorRoundedButton() -> STBtn {
        let button = STHighlightColorBtn(type: .custom)
        button.setTitle("按下变色 + 圆角 + 阴影", for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        button.setTitleColor(.white, for: .normal)
        button.setTitleColor(.white, for: .highlighted)
        button.normalBackgroundColor = .systemGreen
        button.highlightedBackgroundColor = .systemTeal
        button.st_roundedButton(cornerRadius: 14)
        button.st_setShadow(
            color: UIColor.black.withAlphaComponent(0.18),
            offset: CGSize(width: 0, height: 4),
            radius: 10,
            opacity: 1
        )
        button.heightAnchor.constraint(equalToConstant: 52).isActive = true
        button.addTarget(self, action: #selector(self.onHighlightButtonTapped(_:)), for: .touchUpInside)
        return button
    }

    @objc private func onHighlightButtonTapped(_ sender: UIButton) {
        sender.isEnabled = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            sender.isEnabled = true
        }
    }

    // MARK: - STIconBtn 图文位置（LiquidGlass 背景）
    private func makeFilledIconButton(position: STIconPosition, title: String) -> STIconBtn {
        let button = STIconBtn(type: .custom)
        button.setTitle(title, for: .normal)
        button.setImage(UIImage(systemName: "sparkles"), for: .normal)
        button.tintColor = .systemBlue
        button.setTitleColor(.label, for: .normal)
        button.cornerRadius = 18
        button.st_setLiquidGlassBackground()
        button.configure()
            .iconPosition(position)
            .spacing(10)
            .contentInsets(UIEdgeInsets(top: 10, left: 16, bottom: 10, right: 16))
            .done()
        button.heightAnchor.constraint(equalToConstant: position == .top ? 88 : 56).isActive = true
        return button
    }

    // MARK: - STIconBtn 自适应宽度
    /// 借助 `UIStackView(alignment = .leading)` 让每个 `STIconBtn` 以自身 intrinsicContentSize
    /// （`UIButton.Configuration` 原生依据 `contentInsets + imagePlacement + imagePadding` 计算）
    /// 横向收缩到贴合内容，不同文案长度下宽度自动伸缩。
    private func makeAdaptiveIconButtonsRow() -> UIView {
        let container = UIStackView()
        container.axis = .vertical
        container.alignment = .leading
        container.spacing = 10

        container.addArrangedSubview(self.makeAdaptiveIconButton(
            title: "收藏",
            systemIconName: "star.fill",
            iconPosition: .left,
            tint: .systemOrange
        ))
        container.addArrangedSubview(self.makeAdaptiveIconButton(
            title: "下一步",
            systemIconName: "arrow.right.circle.fill",
            iconPosition: .right,
            tint: .systemBlue
        ))
        container.addArrangedSubview(self.makeAdaptiveIconButton(
            title: "按下可变色 · 含较长文本的自适应测试",
            systemIconName: "hand.tap.fill",
            iconPosition: .left,
            tint: .systemPurple
        ))
        container.addArrangedSubview(self.makeAdaptiveIconButton(
            title: "上传",
            systemIconName: "icloud.and.arrow.up.fill",
            iconPosition: .top,
            tint: .systemTeal
        ))
        return container
    }

    private func makeAdaptiveIconButton(
        title: String,
        systemIconName: String,
        iconPosition: STIconPosition,
        tint: UIColor
    ) -> STIconBtn {
        let button = STIconBtn(type: .custom)
        button.setTitle(title, for: .normal)
        button.setTitleColor(.white, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
        if let icon = UIImage(systemName: systemIconName)?.withRenderingMode(.alwaysTemplate) {
            button.setImage(icon, for: .normal)
            button.tintColor = .white
        }
        button.backgroundColor = tint
        button.configure()
            .iconPosition(iconPosition)
            .spacing(8)
            .contentInsets(UIEdgeInsets(top: 10, left: 14, bottom: 10, right: 14))
            .done()
        button.st_roundedButton(cornerRadius: 10)
        return button
    }

    // MARK: - STVerificationCodeBtn
    private func setupVerificationButton() {
        self.verificationButton.setTitle("发送验证码", for: .normal)
        self.verificationButton.setTitleColor(.white, for: .normal)
        self.verificationButton.setTitleColor(.secondaryLabel, for: .disabled)
        self.verificationButton.titleSuffix = "s 后重试"
        self.verificationButton.timerInterval = 10
        self.verificationButton.cornerRadius = 18
        self.verificationButton.st_setGradientBackground(colors: [.systemBlue, .systemCyan])
        self.verificationButton.heightAnchor.constraint(equalToConstant: 56).isActive = true
        self.verificationButton.addTarget(self, action: #selector(self.startVerificationCountdown), for: .touchUpInside)
    }

    @objc private func startVerificationCountdown() {
        self.verificationButton.beginTimer()
    }
}
