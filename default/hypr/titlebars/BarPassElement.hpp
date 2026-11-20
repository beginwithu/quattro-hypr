#pragma once
#include <hyprland/src/render/pass/PassElement.hpp>

class CQuattroFloatingHyprBar;

class CQuattroFloatingBarPassElement : public IPassElement {
public:
  struct SBarData {
    CQuattroFloatingHyprBar *deco = nullptr;
    float a = 1.F;
  };

  CQuattroFloatingBarPassElement(const SBarData &data_);
  virtual ~CQuattroFloatingBarPassElement() = default;

  virtual std::vector<UP<IPassElement>> draw(Render::CRenderContext &ctx) override;
  virtual bool needsLiveBlur(Render::CRenderContext &) override;
  virtual bool needsPrecomputeBlur(Render::CRenderContext &) override;
  virtual std::optional<CBox> boundingBox(Render::CRenderContext &ctx) override;

  virtual const char *passName() override { return "CQuattroFloatingBarPassElement"; }

  virtual ePassElementType type() override { return EK_CUSTOM; }

private:
  SBarData data;
};
